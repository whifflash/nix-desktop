#!/usr/bin/env bash

# start waybar if not started
if ! pgrep "waybar" >/dev/null; then
  waybar &
fi

# current checksums
current_checksum_config=$(md5sum ~/.config/waybar/config)
current_checksum_style=$(md5sum ~/.config/waybar/style.css)
current_checksum_palette=$(md5sum ~/.config/waybar/palette.css)

# loop forever
while true; do
  # new checksums
  new_checksum_config=$(md5sum ~/.config/waybar/config)
  new_checksum_style=$(md5sum ~/.config/waybar/style.css)
  new_checksum_palette=$(md5sum ~/.config/waybar/palette.css)

  # if checksums are different
  if [ "$current_checksum_config" != "$new_checksum_config" ] ||
    [ "$current_checksum_style" != "$new_checksum_style" ] ||
    [ "$current_checksum_palette" != "$new_checksum_palette" ]; then
    # kill waybar
    pkill waybar

    # start waybar
    waybar &

    # update checksums
    current_checksum_config=$new_checksum_config
    current_checksum_style=$new_checksum_style
    current_checksum_palette=$new_checksum_palette
  fi
  sleep 1
done
