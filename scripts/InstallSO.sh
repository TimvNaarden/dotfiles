#!/usr/bin/env bash
# InstallSO — download and install a specific .so file from the Arch Linux Archive

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

usage() {
    echo -e "${BOLD}Usage:${RESET} InstallSO <libname.so.X.Y>"
    echo -e "  Example: ${CYAN}InstallSO libopenvdb.so.12.1${RESET}"
    exit 1
}

[[ $# -lt 1 ]] && usage

SO_NAME="$1"
ALA_BASE="https://archive.archlinux.org/packages"
INSTALL_DIR="/usr/lib"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo -e "\n${BOLD}InstallSO${RESET} — Arch Linux .so installer"
echo -e "─────────────────────────────────────────"
echo -e "Target: ${CYAN}${SO_NAME}${RESET}"

# Derive package name from .so name
PKG_NAME=$(echo "$SO_NAME" | sed 's/^lib//' | sed 's/\.so\..*//')
echo -e "Guessed package: ${CYAN}${PKG_NAME}${RESET}"

# Allow user to override package name
read -rp "$(echo -e ${YELLOW}"Press Enter to use '${PKG_NAME}', or type a different package name: "${RESET})" USER_PKG
[[ -n "$USER_PKG" ]] && PKG_NAME="$USER_PKG"

echo -e "\n${BOLD}Fetching package list from Arch Linux Archive...${RESET}"
ALA_URL="${ALA_BASE}/${PKG_NAME:0:1}/${PKG_NAME}/"

PKG_LIST=$(curl -s "$ALA_URL" | grep -oP "${PKG_NAME}-[^\"]+\.pkg\.tar\.(zst|xz)" | sort -V | uniq)

if [[ -z "$PKG_LIST" ]]; then
    echo -e "${RED}Error: No packages found for '${PKG_NAME}' at:${RESET}"
    echo -e "  $ALA_URL"
    exit 1
fi

echo -e "\n${BOLD}Available packages:${RESET}"
mapfile -t PKG_ARRAY <<< "$PKG_LIST"
for i in "${!PKG_ARRAY[@]}"; do
    echo -e "  ${CYAN}[$i]${RESET} ${PKG_ARRAY[$i]}"
done

read -rp "$(echo -e ${YELLOW}"\nSelect package number: "${RESET})" PKG_IDX
SELECTED_PKG="${PKG_ARRAY[$PKG_IDX]}"
PKG_URL="${ALA_URL}${SELECTED_PKG}"

echo -e "\n${BOLD}Downloading:${RESET} $SELECTED_PKG"
curl -# -L -o "${TMP_DIR}/${SELECTED_PKG}" "$PKG_URL"

echo -e "\n${BOLD}Extracting .so files from package...${RESET}"
if [[ "$SELECTED_PKG" == *.zst ]]; then
    tar -I zstd -xf "${TMP_DIR}/${SELECTED_PKG}" -C "$TMP_DIR" --wildcards "usr/lib/*.so*" 2>/dev/null || true
else
    tar -xJf "${TMP_DIR}/${SELECTED_PKG}" -C "$TMP_DIR" --wildcards "usr/lib/*.so*" 2>/dev/null || true
fi

ALL_SO_FILES=$(find "$TMP_DIR/usr/lib" -name "*.so*" 2>/dev/null | sort)

if [[ -z "$ALL_SO_FILES" ]]; then
    echo -e "${RED}No .so files found in package.${RESET}"
    exit 1
fi

# Ask user whether to show all .so files or only versioned ones (*.so.x.x.x)
echo -e "\n${BOLD}Filter .so files:${RESET}"
echo -e "  ${CYAN}[1]${RESET} Show only versioned files  ${YELLOW}(*.so.1.2.3 — real files with version numbers)${RESET}"
echo -e "  ${CYAN}[2]${RESET} Show all .so files         ${YELLOW}(includes unversioned symlinks like libfoo.so)${RESET}"
read -rp "$(echo -e ${YELLOW}"Choice [1/2, default 1]: "${RESET})" FILTER_CHOICE
FILTER_CHOICE="${FILTER_CHOICE:-1}"

mapfile -t ALL_SO_ARRAY <<< "$ALL_SO_FILES"
SO_ARRAY=()

for FILE in "${ALL_SO_ARRAY[@]}"; do
    BASENAME=$(basename "$FILE")
    if [[ "$FILTER_CHOICE" == "2" ]]; then
        SO_ARRAY+=("$FILE")
    else
        # Only include files whose name matches *.so.<digits>(.<digits>)* — versioned real files
        if echo "$BASENAME" | grep -qP '\.so\.\d+(\.\d+)*$'; then
            SO_ARRAY+=("$FILE")
        fi
    fi
done

if [[ ${#SO_ARRAY[@]} -eq 0 ]]; then
    echo -e "${RED}No matching .so files found with the selected filter.${RESET}"
    exit 1
fi

echo -e "\n${BOLD}Found .so files:${RESET}"
for i in "${!SO_ARRAY[@]}"; do
    FILE="${SO_ARRAY[$i]}"
    BASENAME=$(basename "$FILE")
    TYPE=""
    [[ -L "$FILE" ]] && TYPE="${YELLOW}(symlink)${RESET}" || TYPE="${GREEN}(real file)${RESET}"
    echo -e "  ${CYAN}[$i]${RESET} ${BASENAME} $TYPE"
done

echo -e "\nEnter comma-separated numbers to install (e.g. 0,2), or ${CYAN}a${RESET} for all:"
read -rp "$(echo -e ${YELLOW}"Selection: "${RESET})" SELECTION

if [[ "$SELECTION" == "a" ]]; then
    INDICES=("${!SO_ARRAY[@]}")
else
    IFS=',' read -ra INDICES <<< "$SELECTION"
fi

echo ""
for IDX in "${INDICES[@]}"; do
    IDX=$(echo "$IDX" | tr -d ' ')
    FILE="${SO_ARRAY[$IDX]}"
    BASENAME=$(basename "$FILE")
    DEST="${INSTALL_DIR}/${BASENAME}"

    if [[ -L "$FILE" ]]; then
        # Symlink — resolve and copy real target instead
        REAL_TARGET=$(readlink -f "$FILE" 2>/dev/null || true)
        if [[ -n "$REAL_TARGET" && -f "$REAL_TARGET" ]]; then
            echo -e "${YELLOW}Symlink detected → installing real target:${RESET} $(basename "$REAL_TARGET") as ${BASENAME}"
            sudo cp "$REAL_TARGET" "$DEST"
        else
            echo -e "${YELLOW}Warning: Symlink target not found, skipping:${RESET} $BASENAME"
            continue
        fi
    else
        echo -e "Installing: ${CYAN}${BASENAME}${RESET} → ${INSTALL_DIR}/"
        sudo cp "$FILE" "$DEST"
    fi

    sudo chmod 755 "$DEST"
    echo -e "${GREEN}✓ Installed:${RESET} $DEST"
done

echo -e "\n${BOLD}Updating linker cache (ldconfig)...${RESET}"
sudo ldconfig
echo -e "${GREEN}✓ Done! ldconfig updated.${RESET}\n"
