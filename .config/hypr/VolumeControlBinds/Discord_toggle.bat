pactl set-sink-input-mute $(pactl list sink-inputs | awk '/Sink Input #/ {id=$3; sub("#","",id)} /media.name = "Discord"/ {print id; exit}') toggle
