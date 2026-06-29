#!/usr/bin/env bash

# Fetch items, split on newlines using char code 10, and join with visual arrows
list_items=$(copyq eval "var res=[]; for(var i=0; i<size(); ++i){ var txt=str(read(i)).split(String.fromCharCode(10)).join(' ↵ ').substring(0,100); res.push(i+': '+txt); }; res.join(String.fromCharCode(10));")

# Open Wofi list
selected=$(echo "$list_items" | wofi --dmenu --prompt "Clipboard:")

# Extract the index and select the true multi-line object from CopyQ
if [ -n "$selected" ]; then
    idx=$(echo "$selected" | cut -d':' -f1)
    copyq select "$idx"
    sleep 0.15

    # Get the window class of the active window
    active_class=$(hyprctl activewindow -j | jq -r '.class')

    # Send Ctrl+Shift+V if inside a terminal application
    case "$active_class" in
        "kitty"|"alacritty"|"foot"|"WezTerm"|"ghostty")
            wtype -M ctrl -M shift v -m ctrl -m shift
            ;;
        *)
            wtype -M ctrl v -m ctrl
            ;;
    esac
fi
