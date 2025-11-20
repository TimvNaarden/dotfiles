#!/bin/bash
STATE="/home/tim/.spotify-volume"
DEFAULT="80%"

# Load last known volume, or use default
if [ -f "$STATE" ]; then
    TARGET=$(cat "$STATE")
    echo "[DEBUG] Loaded saved volume: $TARGET"
else
    TARGET="$DEFAULT"
    echo "[DEBUG] No saved volume, using default: $TARGET"
fi

save_volume() {
    echo "$1" > "$STATE"
    echo "[DEBUG] Saved new volume: $1"
}

get_volume() {
    pactl list sink-inputs | awk -v T="$1" '
        /Sink Input #/ {sid=$3; sub("#","",sid)}
        sid==T && /Volume:/ {
            if (match($0, /([0-9]+)%/, m)) {
                print m[1] "%"
                exit
            }
        }
    '
}
id1=$(pactl list sink-inputs | awk '
    /Sink Input #/ {id=$3; sub("#","",id)}
    /media.name = "Spotify"/ {print id; exit}
')
current1=$(get_volume "$id1")
current=${current1%?}
is_spotify() {
    pactl list sink-inputs | awk -v T="$1" '
        /Sink Input #/ {sid=$3; sub("#","",sid)}
        sid==T && /application.name = "Spotify"/ {found=1}
        END {exit found?0:1}
    '
}

echo "[DEBUG] Starting Spotify volume watcher..."

declare -A pending_remove

pactl subscribe | grep --line-buffered "sink-input" | while read -r line; do
    echo "[DEBUG] Event: $line"

    id=$(sed -n 's/.*#\([0-9]\+\).*/\1/p' <<< "$line")
    [ -z "$id" ] && continue

    if is_spotify "$id"; then
        case "$line" in
            *"Event 'new'"*)
                echo "[DEBUG] New Spotify sink-input #$id → applying volume $TARGET"
                pactl set-sink-input-volume "$id" "$TARGET"
                unset pending_remove["$id"]
                ;;
            *"Event 'change'"*)
                v=$(get_volume "$id")
                v1=${v%?}
                diff=$(( v1 > current ? v1 - current : current -v1))
                if [ -n "$v" ] && [ "$v" != "$TARGET" ] && [ "$diff" -lt 3 ]; then
                    echo "[DEBUG] Spotify sink-input #$id volume changed by user → $v"
                    TARGET="$v"
                    save_volume "$TARGET"
                    current=${TARGET%?}
                fi
                if [ "$diff" -gt 2 ]; then
                    pactl set-sink-input-volume "$id" "$TARGET"
                    echo "[DEBUG] Stopped reset to 100%"
                fi

                ;;
            *"Event 'remove'"*)
                echo "[DEBUG] Spotify sink-input #$id removed"
                pending_remove["$id"]=1
                ;;
        esac
    fi
done
