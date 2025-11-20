pactl set-sink-input-mute $(pactl list sink-inputs | awk '/Sink Input #/ {id=$3; sub("#","",id)} /application.name = "Discord"/ {print id; exit}') toggle
