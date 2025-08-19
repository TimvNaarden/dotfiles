pactl set-sink-input-volume $(pactl list sink-inputs | awk '/Sink Input #/ {id=$3; sub("#","",id)} /media.name = "Discord"/ {print id; exit}') +2%
