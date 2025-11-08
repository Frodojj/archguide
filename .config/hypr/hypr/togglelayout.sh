#!/usr/bin/env bash
# Copyright 2025 Jimmy Cerra 
# MIT license: Permission granted to use without restriction as long as the
# copyright and license are included with all whole or substantial copies.
# PROVIDED "AS IS" WITH NO WARRANTY. THE AUTHOR(S) ARE NOT LIABLE FOR DAMAGES.
# Script for changing Hyprland Layouts (Master or Dwindle) on fly

OUTPUT=$(hyprctl getoption general:layout | head -n 1)
LAYOUT=${OUTPUT:5}
case $LAYOUT in
    "master")
	    hyprctl keyword general:layout dwindle
        notify-send -eu normal -a "Hyprland" -t 2000 "Master layout"
	    ;;
    "dwindle")
	    hyprctl keyword general:layout master
        notify-send -eu normal -a "Hyprland" -t 2000 "Dwindle layout"
	    ;;
    *) ;;
esac
