#!/usr/bin/env bash

# Script for changing Hyprland Layouts (Master or Dwindle) on fly

OUTPUT=$(hyprctl getoption general:layout | head -n 1)
LAYOUT=${OUTPUT:5}
case $LAYOUT in
    "master")
	    hyprctl keyword general:layout dwindle
	    ;;
    "dwindle")
	    hyprctl keyword general:layout master
	    ;;
    *) ;;
esac
