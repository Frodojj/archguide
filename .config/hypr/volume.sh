#!/bin/bash
# Copyright 2025 Jimmy Cerra 
# MIT license: Permission granted to use without restriction as long as the
# copyright and license are included with all whole or substantial copies.
# PROVIDED "AS IS" WITH NO WARRANTY. THE AUTHOR(S) ARE NOT LIABLE FOR DAMAGES.

notify_volume() {
	declare vol=$(wpctl get-volume $1)
	declare msg="Volume"
	
	if [[ "$vol" == *"MUTE"* ]]; then
		msg="Muted, $msg"
	fi
	
	if [[ "$1" == *"SOURCE"* ]]; then
		msg="Mic $msg"
	fi
	
	# Remove letters, spaces, punct, and leading zeroes
	declare -i val=$(
		echo "$vol" | 
		tr -d '[[:alpha:][:space:][:punct:]]' | 
		sed 's/^0*//'
	)
	
	notify-send -eu low "$msg $val%" -h int:value:"$val" \
		-h string:x-canonical-private-synchronous:volume \
		-t 1500
}

cli() {
	echo "$@"
	declare cmd="$1"
	shift
	case "$cmd" in
		vol)
			wpctl set-volume "$@"
			notify_volume "$1"
			;;
		mute)
			wpctl set-mute "$@"
			notify_volume "$1"
			;;
		*)
			echo "Unknown Command"
			;;
	esac
}

cli "$@"
