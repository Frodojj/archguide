#!/bin/bash -e
# Copyright 2025 Jimmy Cerra 
# MIT license: Permission granted to use without restriction as long as the
# copyright and license are included with all whole or substantial copies.
# PROVIDED "AS IS" WITH NO WARRANTY. THE AUTHOR(S) ARE NOT LIABLE FOR DAMAGES.

# Prints the next line of FILE after the one that matches
# or the first line if no match or matched last line
# usage: cat FILE | findNextLine MATCH
findNextLine() {
	awk '
		FNR == 1 {fst = $0}
		$0 == "'"$1"'" {if ((getline nxt) > 0) {print nxt} ; exit}
		ENDFILE {print fst}
	'
	cat > /dev/null # Read rest of file to avoid Broken pipe error
}

# Prints the last value of FILE with lines
# text = value
# like the output of hyprctl hyprpaper listactive
# usage: cat FILE | lastValue
lastValue() {
	sed 's/^[^=]*= \?//' | tail -n 1
}

# Loads the next image into hyprpaper from BGS_FOLDER_PATH
# If no match or next image, then loads first image
# usage: loadNextBG BGS_FOLDER_PATH
loadNextBG() {
	shopt -s extglob # so +() works
	declare path="${1%%+(/)}" # Removes all trailing /
	declare active=$(hyprctl hyprpaper listactive | lastValue)
	declare next=$(ls -1Nd "$path"/* | findNextLine "$active")
	echo "Attempting to load: $next"
	hyprctl hyprpaper reload ",$next"
	hyprctl hyprpaper unload unused
}

# If hyprpaper isn't running, then run it!
if [[ -z "$(pgrep hyprpaper)" ]]; then
	hyprctl dispatch exec hyprpaper
fi

loadNextBG $1

