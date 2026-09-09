#!/usr/bin/env bash
# install-wsl-shell — zsh, zoxide and tmux on Debian/Ubuntu (including WSL2)
#
# Installs the shell stack this repo's .zshrc and .tmux.conf expect, then links
# both into place. Safe to re-run: every step checks before acting, and a real
# file found where a symlink belongs is moved aside rather than clobbered.
#
# Usage: scripts/install-wsl-shell.sh [--no-chsh] [--no-tmux-plugins]

set -euo pipefail

BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; CYAN='\033[0;36m'; DIM='\033[2m'; RESET='\033[0m'

DO_CHSH=1
DO_TMUX_PLUGINS=1
for arg in "$@"; do
    case "$arg" in
        --no-chsh)         DO_CHSH=0 ;;
        --no-tmux-plugins) DO_TMUX_PLUGINS=0 ;;
        -h|--help)         sed -n '2,9p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo -e "${RED}unknown option: $arg${RESET}" >&2; exit 1 ;;
    esac
done

# Resolve the repo through the symlink, so this works whether it is run from
# ~/dotfiles/scripts or from ~/scripts after stowing.
REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

step() { echo -e "\n${BOLD}==>${RESET} ${BOLD}$*${RESET}"; }
ok()   { echo -e "  ${GREEN}ok${RESET}      $*"; }
skip() { echo -e "  ${DIM}skip${RESET}    $*"; }
warn() { echo -e "  ${YELLOW}warn${RESET}    $*"; }
die()  { echo -e "\n${RED}error${RESET}   $*" >&2; exit 1; }

command -v apt-get >/dev/null || die "no apt-get: this script targets Debian/Ubuntu."
[ -d "$REPO/.config/tmux" ] || die "not a dotfiles checkout: $REPO"

echo -e "${BOLD}install-wsl-shell${RESET} — zsh, zoxide, tmux"
echo -e "─────────────────────────────────────────"
echo -e "Repo:   ${CYAN}${REPO}${RESET}"
grep -qi microsoft /proc/version 2>/dev/null \
    && echo -e "Host:   ${CYAN}WSL${RESET}" \
    || echo -e "Host:   ${CYAN}native Debian/Ubuntu${RESET} ${DIM}(fine, nothing here is WSL-only)${RESET}"

# ---------------------------------------------------------------- symlinks ----
# Relative targets, matching the form stow uses, so a later `stow .` on this
# machine adopts them instead of reporting a conflict.
link() { # link <repo-relative path> <target under $HOME>
    local src="$REPO/$1" dst="$HOME/$2" rel
    [ -e "$src" ] || { warn "$1 missing from the repo, skipping"; return 0; }
    mkdir -p "$(dirname "$dst")"
    rel="$(realpath --relative-to="$(dirname "$dst")" "$src")"

    if [ -L "$dst" ]; then
        if [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
            skip "$2 already linked"
            return 0
        fi
        rm "$dst"
    elif [ -e "$dst" ]; then
        local backup="$dst.bak-$(date +%Y%m%d-%H%M%S)"
        mv "$dst" "$backup"
        warn "$2 was a real file, moved to $(basename "$backup")"
    fi

    ln -s "$rel" "$dst"
    ok "$2 -> $rel"
}

# ---------------------------------------------------------------- packages ----
step "System packages"
NEED=()
for p in zsh tmux git curl ca-certificates python3; do
    dpkg -s "$p" >/dev/null 2>&1 || NEED+=("$p")
done
# zoxide is packaged from Debian bookworm onward. Where it is missing the
# upstream installer below covers it.
if ! command -v zoxide >/dev/null 2>&1; then
    cand="$(apt-cache policy zoxide 2>/dev/null | awk '/Candidate:/{print $2}')"
    case "$cand" in
        ""|"(none)") ;;          # not in the archive; upstream installer below
        *) NEED+=(zoxide) ;;
    esac
fi

if [ ${#NEED[@]} -gt 0 ]; then
    echo -e "  installing: ${CYAN}${NEED[*]}${RESET}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq "${NEED[@]}"
    ok "apt packages installed"
else
    skip "all apt packages already present"
fi

# ------------------------------------------------------------------ zoxide ----
step "zoxide"
# .zshrc line 10 is an unguarded `eval "$(zoxide init zsh)"`, so without zoxide
# every new shell prints "command not found". It is not optional here.
if command -v zoxide >/dev/null 2>&1; then
    skip "already installed ($(zoxide --version 2>/dev/null | head -1))"
else
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh -o "$tmp/zoxide.sh"
    # Inspectable rather than piped straight into a shell.
    sh "$tmp/zoxide.sh" --bin-dir "$HOME/.local/bin"
    rm -rf "$tmp"; trap - EXIT
    if [ -x "$HOME/.local/bin/zoxide" ]; then
        ok "installed to ~/.local/bin (already on PATH via .zshrc)"
    else
        die "zoxide install reported success but no binary at ~/.local/bin/zoxide"
    fi
fi

# ---------------------------------------------------------------- oh-my-zsh ----
step "oh-my-zsh"
# Link .zshrc first: the installer leaves an existing one alone given
# --keep-zshrc, so the symlink survives. The other order replaces it with the
# oh-my-zsh template and your edits stop reaching the repo.
link ".zshrc" ".zshrc"

if [ -d "$HOME/.oh-my-zsh" ]; then
    skip "already installed"
else
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended --keep-zshrc
    ok "installed"
fi

# .zshrc line 6 names two plugins oh-my-zsh does not bundle. Without them zsh
# prints an error on every start.
step "zsh plugins"
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
for spec in \
    "zsh-users/zsh-autosuggestions:zsh-autosuggestions" \
    "zsh-users/zsh-syntax-highlighting:zsh-syntax-highlighting"; do
    repo="${spec%%:*}"; name="${spec##*:}"
    if [ -d "$ZSH_CUSTOM/plugins/$name/.git" ]; then
        skip "$name"
    else
        git clone -q --depth 1 "https://github.com/$repo" "$ZSH_CUSTOM/plugins/$name"
        ok "$name"
    fi
done

# -------------------------------------------------------------------- tmux ----
step "tmux"
link ".tmux.conf"    ".tmux.conf"
link ".config/tmux"  ".config/tmux"

# TPM is deliberately not vendored: it used to be a gitlink with no .gitmodules,
# which produced empty plugin directories on a fresh clone.
if [ -d "$HOME/.tmux/plugins/tpm/.git" ]; then
    skip "tpm already cloned"
else
    git clone -q --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    ok "tpm cloned"
fi

if [ "$DO_TMUX_PLUGINS" = 1 ]; then
    if "$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null 2>&1; then
        ok "plugins installed ($(find "$HOME/.tmux/plugins" -maxdepth 1 -mindepth 1 -type d | wc -l) dirs)"
    else
        warn "headless plugin install failed; open tmux and press prefix + I (prefix is Ctrl-s)"
    fi
else
    skip "plugin install (--no-tmux-plugins)"
fi

# ------------------------------------------------------------- login shell ----
step "Login shell"
if [ "$(basename "${SHELL:-}")" = "zsh" ]; then
    skip "already zsh"
elif [ "$DO_CHSH" = 0 ]; then
    skip "chsh (--no-chsh); run: chsh -s \"\$(command -v zsh)\""
else
    echo -e "  ${DIM}chsh needs your password${RESET}"
    if chsh -s "$(command -v zsh)"; then
        ok "default shell set to zsh (takes effect on next WSL launch)"
    else
        warn "chsh failed; run it yourself: chsh -s \"\$(command -v zsh)\""
    fi
fi

# ------------------------------------------------------------------ report ----
step "Verification"
fail=0
for c in zsh tmux zoxide git python3; do
    if command -v "$c" >/dev/null 2>&1; then ok "$c  $(command -v "$c")"
    else echo -e "  ${RED}FAIL${RESET}    $c not on PATH"; fail=1; fi
done
for l in .zshrc .tmux.conf .config/tmux; do
    if [ -L "$HOME/$l" ]; then ok "$l -> $(readlink "$HOME/$l")"
    else echo -e "  ${RED}FAIL${RESET}    $l is not a symlink"; fail=1; fi
done
[ -d "$HOME/.oh-my-zsh" ] && ok "oh-my-zsh" || { echo -e "  ${RED}FAIL${RESET}    oh-my-zsh"; fail=1; }

# The one thing that cannot be checked without actually starting zsh: a broken
# .zshrc only shows up as noise on every new shell.
step "Starting a login zsh to catch config errors"
if err="$(zsh -i -c exit 2>&1)" && [ -z "$err" ]; then
    ok "clean start, no output"
else
    warn "zsh printed something on start:"
    echo "$err" | sed 's/^/          /'
    echo -e "          ${DIM}A hardcoded /home/tim path in .zshrc is the usual cause.${RESET}"
    echo -e "          ${DIM}See INSTALL-debian-wsl.md, the ghcup note.${RESET}"
fi

if [ "$fail" = 0 ]; then
    echo -e "\n${GREEN}${BOLD}Done.${RESET} Open a new shell, or run ${CYAN}exec zsh -l${RESET}."
    echo -e "${DIM}Neovim is a separate job: see INSTALL-debian-wsl.md.${RESET}"
else
    die "some checks failed, see FAIL lines above"
fi
