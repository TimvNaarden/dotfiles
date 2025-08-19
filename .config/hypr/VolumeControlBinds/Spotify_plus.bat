pactl set-sink-input-volume $(pactl list sink-inputs | awk '/Sink Input #/ {id=$3; sub("#","",id)} /media.name = "Spotify"/ {print id; exit}') +2%
