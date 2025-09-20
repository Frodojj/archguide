#!/bin/bash -e
# Copyright 2025 Jimmy Cerra 
# MIT license: Permission granted to use without restriction as long as the
# copyright and license are included with all whole or substantial copies.
# PROVIDED "AS IS" WITH NO WARRANTY. THE AUTHOR(S) ARE NOT LIABLE FOR DAMAGES.


save_brightness() {
	# Store variable in hyprctl process
	hyprctl keyword env BRIGHTNESS,$(ddcutil -t getvcp 10 | awk '{print $4}')
}

set_brightness() {
	hyprctl dispatch exec ddcutil setvcp 10 "$1"
}

restore_brightness() {
	# Variable needs interpreted by hyprctl process rather than this process
	hyprctl dispatch exec ddcutil setvcp 10 \$BRIGHTNESS
}

case "$1" in
	save)
		save_brightness
		if [ "$#" -eq 2 ]; then
			set_brightness "$2"
		fi
		;;
	set)
		set_brightness "$2"
		;;
	restore)
		restore_brightness
		;;
	*)
		echo "params: save [optional new int value] | set [new int value] | restore"
		;;
esac
