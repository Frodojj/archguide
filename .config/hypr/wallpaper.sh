#!/bin/bash -e
# Copyright 2025 Jimmy Cerra 
# MIT license: Permission granted to use without restriction as long as the
# copyright and license are included with all whole or substantial copies.
# PROVIDED "AS IS" WITH NO WARRANTY. THE AUTHOR(S) ARE NOT LIABLE FOR DAMAGES.

# usage: cat FILE | lastValue
lastValue() {
	sed 's/^[^=]*= \?//' | tail -n 1
}

# usage: cat FILE | findNextLine MATCH
findNextLine() {
	awk 'FNR == 1 {fst = $0}
	$0 == "'"$1"'" {
		if ((getline nxt) > 0) print nxt
		else print fst
		exit
	}'
}

# usage: loadNextBG BGS_FOLDER_PATH
loadNextBG() {
	declare active=$(hyprctl hyprpaper listactive | lastValue)
	declare next=$(ls -1Nd "$1"/* | findNextLine "$active")
	hyprctl hyprpaper reload ",$next"
	hyprctl hyprpaper unload unused
}

loadNextBG ~/Backgrounds
