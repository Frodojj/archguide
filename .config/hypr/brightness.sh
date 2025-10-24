#!/usr/bin/env bash
# Copyright 2025 Jimmy Cerra 
# MIT license: Permission granted to use without restriction as long as the
# copyright and license are included with all whole or substantial copies.
# PROVIDED "AS IS" WITH NO WARRANTY. THE AUTHOR(S) ARE NOT LIABLE FOR DAMAGES.

get_brightness() {
	ddcutil -t getvcp 10 | awk '{print $4}'
}

save_brightness() {
	# Store variable in hyprctl process
	hyprctl keyword env SAVED_BRIGHTNESS,$(get_brightness)
}

set_brightness() {
	ddcutil --noverify setvcp 10 "$@"
}

restore_brightness() {
	# Variable needs interpreted by hyprctl process rather than this process
	hyprctl dispatch exec ddcutil setvcp 10 \$SAVED_BRIGHTNESS
}

cli() {
	echo "$@"
	declare cmd="$1"
	shift
	case "$cmd" in
		notify)
			if [ "$#" -gt 0 ]; then
				cli "$@"
			fi
			declare -i val="$(get_brightness)"
			notify-send -eu low "$val%" -h int:value:"$val" \
				-a "Brightness" \
				-h string:x-canonical-private-synchronous:brightness\
				-t 2000
			;;
		save)
			save_brightness
			if [ "$#" -gt 0 ]; then
				cli "$@"
			fi
			;;
		set)
			set_brightness "$@"
			;;
		get)
			get_brightness
			;;
		restore)
			restore_brightness
			;;
		*)
			echo "params: notify <cmds>* | get | set [+-]? <int> | save <cmds>* | restore"
			;;
	esac
}

cli "$@"
