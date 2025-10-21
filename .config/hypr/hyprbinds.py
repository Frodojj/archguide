#! /usr/bin/python
"""
Copyright 2025 Jimmy Cerra
MIT license: Permission granted to use without restriction as long as
the copyright and license are included with all whole or substantial
copies. PROVIDED "AS IS" WITH NO WARRANTY. THE AUTHOR(S) ARE NOT LIABLE
FOR DAMAGES.

Usage: hyprctl -j binds | ./.config/hypr/hyprbinds.py -k
"""

import json
import re
import sys

from argparse import ArgumentParser
from contextlib import redirect_stdout
from io import StringIO
from shutil import get_terminal_size


__all__ = ["print_cols", "print_bind"]


# ANSI CS Introducer + params + intermeds (2 parts) + final
ANSI_CSI = r"\N{ESC}\[" \
         + r"[0-9:;<=>?]*" \
         + r'[!"#$%&' + r"'()*+,-./]*" \
         + r"[@A-Z\[\\\]^_`a-z{|}~]"


ANSI_ESC_RE = re.compile(ANSI_CSI)


# Key:  shft caps ctl  alt  num  mod3 sup  altg
#MODS = ["⇧", "⇪", "⌃", "⎇", "⇭", "✦", "❖", "ᴳ"]
MODS_LIST = {
    "⇧": "Shift",
    "⇪": "Caps lock",
    "^": "Control",
    "*": "Alt",
    "⇭": "Num Lock",
    "◇": "Meta",
    "❖": "Super",
    "ᴳ": "Alt Gr"
}


MODS, MODS_DESC = zip(*MODS_LIST.items())


MAIN_INDEX = 6 # Super/Windows/Command Key ⌘


ARGS = {
    "u": "up",
    "d": "down",
    "l": "left",
    "r": "right",
    "movewindow": "Moves window",
    "resizewindow": "Resizes window",
}


DISPATCHERS = {
    "exec": "{description}",
    "killactive": "Closes window",
    "forcekillactive": "Kills window",
    "exit": "Exits hyprland",
    "togglesplit": "Changes split direction",
    "pseudo": "Toggle window span",
    "swapnext": "Swap with adjacent",
    "togglefloating": "Toggle float/tile",
    "resizeactive": "Resize to {arg}",
    "movefocus": "Move focus {arg}",
    "mouse": "{arg}",
    "workspace": "Goto workspace {arg}",
    "togglespecialworkspace": "Toggle special:{arg}", # (⭫⭭)
    "movetoworkspace": "Move to workspace {arg}",
    "movetoworkspacesilent": "Send to {arg}", # (⭫ 🗖 □ ■ ❏)
}


KEYS = {
    "delete": "⨯❭", # ᴅᴇʟ 🅳🅴🅻 🄳🄴🄻 🆥 🠶 ⌦ ⨯❭ ■▮▬▶
    "equal": "=",
    "escape": "⎋",
    "period": ".",
    "super_l": MODS[MAIN_INDEX][0],
    "tab": "⎹⮀⎸", # ⭾ ⮆ tab 
    "up": "▲", # ▴▲🡑
    "down": "▼", # ▾▼🡓
    "left": "◀", # ◂◀🡐
    "right": "▶", # ▸▶🡒
    "prev": "⇞",
    "next": "⇟",
    "home": "⤒",
    "end":  "⤓",
    "mouse:272": "˙🖰",
    "mouse:273": "🖰˙",
    "mouse_up": "🖰⭫", # ⮤⮥ ⭫
    "mouse_down": "🖰⭭", # ⮦⮧ ⭭
    "xf86search": "⌕", # emoji=2sp; \u0007=del; 🔍 ⌕=telephone rec
    "xf86audioraisevolume": "🠙🕨",
    "xf86audiolowervolume": "🠗🕨",
    "xf86audiomute": "×🕨",
    "xf86audiomicmute": "ˣ🎙",
    "xf86audionext": "⏭", # ►►⎸⏭
    "xf86audiopause": "⏸",
    "xf86audioplay": "⏯", # ⏯ ►⏸
    "xf86audioprev": "⏮", # ⏮ ⎹◄◄
    "xf86monbrightnessup": "🠙☼",
    "xf86monbrightnessdown": "🠗☼",
}


KEYS_DESC = {
    KEYS["delete"]: "Delete",
    KEYS["escape"]: "Escape",
    KEYS["tab"]: "Tab",
    KEYS["up"]: "Up",
    KEYS["down"]: "Down",
    KEYS["left"]: "Left",
    KEYS["right"]: "Right",
    KEYS["prev"]: "Pgup",
    KEYS["next"]: "Pgdn",
    KEYS["home"]: "Home",
    KEYS["end"]: "End",
    KEYS["mouse:272"]: "Right click",
    KEYS["mouse:273"]: "Left click",
    KEYS["mouse_up"]: "Scroll-wheel up ",
    KEYS["mouse_down"]: "Scroll-wheel down",
    KEYS["xf86search"]: "Search",
    KEYS["xf86audioraisevolume"]: "Raise vol",
    KEYS["xf86audiolowervolume"]: "Lower vol",
    KEYS["xf86audiomute"]: "Mute vol",
    KEYS["xf86audiomicmute"]: "Mute mic",
    KEYS["xf86audionext"]: "Next track",
    KEYS["xf86audiopause"]: "Pause track",
    KEYS["xf86audioplay"]: "Play track",
    KEYS["xf86audioprev"]: "Prev track",
    KEYS["xf86monbrightnessup"]: "Raise brightness",
    KEYS["xf86monbrightnessdown"]: "Lower brightness"
}


class StringIOMetrics(StringIO):
    """
    StringIO file class that remembers metrics about what's printed,
    currently only the printing length of the longest line.
    """
    # TODO: Make work better by subtracting newlines from length
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.longest = 0
    def write(self, s, /) -> int:
        self.longest = max(self.longest, len(s) - escape_length(s))
        return super().write(s)


def cli():
    """
    Command line arguments to collimate list. 
    Don't need these anymore, but still nice to have.
    """
    columns, *_ = get_terminal_size(fallback=(80,20))
    parser = ArgumentParser()
    parser.add_argument("-b", "--bind-width", type=int, default=8,
                        help = "min width of key-binding; default: 8")
    parser.add_argument("-d", "--desc-width", type=int, default=0,
                        help = "min width of description; default: 0")
    parser.add_argument("-k", "--key", action="store_true",
                        help = "Print list of key symbols")
    parser.add_argument("-n", "--hide", action="store_true",
                        help = "Hides list of key-bindings")
    parser.add_argument("-s", "--spacing", type=int, default=2,
                        help = "Number of spaces between columns; default: 2")
    parser.add_argument("-w", "--width", type=int, default=columns,
                        help = f"Width of print area; defaults to terminal \
                                 width/columns, currently: {columns}")
    return parser.parse_args()


def escape_length(text:str):
    """Length of non-printing escape codes in text."""
    return sum(len(esc) for esc in ANSI_ESC_RE.findall(text))

def format_bind(*, bad: str | tuple[str, ...] = (" ", "⎹", "（", "˙"),
                key: str = "", modmask: str | int = 0, sep: str = " ",
                **_)-> str:
    """
    Makes a key-binding string from a mask and a keyboard key properties in
    the json row. Some characters (bad) in key strings don't look good with
    with spaces, so no space is added. Also key not displayed if key
    is in mod string, since that's confusing for users.
    """
    m = sep.join(unmask(int(modmask), MODS, MAIN_INDEX))
    k = sub(key, KEYS)
    if not m:
        # So K instead of sepK
        return k
    if k in m:
        # So M instead of MsepM
        return m
    if sep == " " and k.startswith(bad):
        # Don't add sep for problematic chars
        return f"{m}{k}"
    # Default
    return f"{m}{sep}{k}"


def format_desc(*, arg: str = "", description: str = "",
                 dispatcher: str = "", **_) -> str:
    """Makes a description string from properties in the json row."""
    a = sub(arg, ARGS)
    disp = sub(dispatcher, DISPATCHERS)
    return disp.format(arg=a, description=description).strip()


def print_bind(row: dict[str, str], layout: str = "{} {}"):
    """Prints a row from the json."""
    desc = row["description"]

    #Interpret directives in description
    if desc.startswith("!skip"):
        return None
    if desc.startswith("!br"):
        row["description"] = desc.removeprefix("!br")
        print()

    b = format_bind(**row)
    d = format_desc(**row)
    s = layout.format(b, d)
    print(s)
    return None


def print_cols(lines: list[str], cols: int = 3, width: int = 24, *,
               pre: str = "", end: str = "\n"):
    """
    Prints a list of lines of text in columns. Before the text is pre,
    and after is end (which has the new line).
    """
    length = len(lines)
    rows = round_up(length / cols)
    for row in range(0, rows):
        out = ""
        for col in range(0, cols):
            index = row + col * rows
            if index >= length:
                break
            line = lines[index]
            # To account for ANSI escapes/colors
            total_width = width + escape_length(line)
            out += f"{pre}{line:{total_width}}"
        print(out, end=end)


def round_up(x) -> int:
    """Rounds up a number."""
    return int(x) + bool(x % 1)


def sub(key: str, subs: dict[str, str]):
    """Substitute key with val in subs if key's in there (lowercase)."""
    return subs.get(key.casefold(), key)


def unmask(mask: int, reps: tuple | list, first: int = 0) -> list:
    """
    Converts mask into a list in reps. First item in list reps[first] if
    found then in byte place order (0->end).
    """
    found = [reps[first]] if(mask >> first & 1) else []
    mask &= ~ (1 << first) # remove first one
    length = len(reps)
    found += [reps[i] for i in range(length) if mask >> i & 1]
    return found


def main() -> int:
    """Runs when script is run."""
    # Prints in color!
    # Look up colors: https://en.wikipedia.org/wiki/ANSI_escape_code
    magenta = "\N{ESC}[95m"
    # blue = \N{ESC}[94m
    # yellow = \N{ESC}[93m
    # green = \N{ESC}[92m
    # red = \N{ESC}[91m
    revert = "\N{ESC}[m"

    args = cli()
    desc_w = args.desc_width
    bind_w = max(args.bind_width - 1, 0) # because extra space in layout
    layout = f"{{:{bind_w}}} {{:{desc_w}}}"
    heading = magenta + "{}" + revert

    print() # Whitespace
    with StringIOMetrics() as buf, redirect_stdout(buf):
        if args.key:
            print(heading.format("Modifier key symbols:"))
            for kb, d in MODS_LIST.items():
                print(layout.format(kb, d))
            print()
            print(heading.format("Other keyboard symbols:"))
            for kb, d in KEYS_DESC.items():
                print(layout.format(kb, d))
            print()
        if not args.hide:
            print(heading.format("Key-bindings:"))
            json.load(sys.stdin, object_hook=lambda b: print_bind(b, layout))
        lines = buf.getvalue()

    width = buf.longest + args.spacing
    cols = args.width // width
    print_cols(lines.splitlines(), cols, width)
    return 0


if __name__ == '__main__':
    sys.exit(main())
