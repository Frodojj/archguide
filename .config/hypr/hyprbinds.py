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


# Prints in color!
# Look up colors: https://en.wikipedia.org/wiki/ANSI_escape_code
MAGENTAC = "\N{ESC}[95m"
BLUEC = "\N{ESC}[94m"
YELLOWC = "\N{ESC}[93m"
GREENC = "\N{ESC}[92m"
REDC = "\N{ESC}[91m"
ENDC = "\N{ESC}[m"
HC = [ ENDC, MAGENTAC, BLUEC, YELLOWC, GREENC, REDC ]


# Key:  shft  caps ctl  alt  num  hyp  sup  altg
#MODS = ["⇧", "$", "⌃", "*", "#", "✦", "!", "ᴳ"]
#MODS = ["_", "|", "⌃", "*", "#", "?", "!", "~"]
#MODS = ["_⇧", "⇪⇫🅲🅰🄰", "^⌃⎈✲", "*°⎇⌥⇮ªᵃᵅᴬ", "#⇭🅽", "✦✧", "!❖⌘◆◇", "ᵍᴳ⎄⎅"]
MODS_LIST = {
    "⇧": "Shift",
    "⇪": "Caps lock",
    "⌃": "Control",
    "*": "Alt",
    "⇭": "Num Lock",
    "✦": "Hypr",
    "❖": "Super",
    "ᵍ": "Alt Gr"
}


MODS, MODS_DESC = zip(*MODS_LIST.items())


MAIN_INDEX = 6 # Super/Windows/Command Key ⌘


ARGS = {
    "u": "up",
    "d": "down",
    "l": "left",
    "r": "right",
    "movetoroot": "Make root window",
    "movewindow": "Move window",
    "orientationbottom": "Main on bottom",
    "orientationleft": "Main on left",
    "orientationright": "Main on right",
    "orientationtop": "Main on top",
    "resizewindow": "Resize window",
    "swapnext": "Swap windows",
    "swapnext noloop": "Move down stack",
    "swapnext loop": "Swap down stack",
    "swapprev noloop": "Move up stack",
    "swapprev loop": "Sway up stack",
    "swapsplit": "Swap split",
    "swapwithmaster": "Swap main window",
    "swapwithmaster ignoremaster": "Make main window",
    "togglesplit": "Change split direction",
}


DISPATCHERS = {
    "exec": "{description}",
    "killactive": "Close window",
    "forcekillactive": "Kill window",
    "fullscreen": "Toggle maximize",
    "exit": "Exits hyprland",
    "togglesplit": "Change split direction",
    "layoutmsg": "{arg}",
    "pseudo": "Toggle window span",
    "swapnext": "Swap with adjacent",
    "togglefloating": "Toggle float",
    "resizeactive": "Resize to {arg}",
    "movefocus": "Move focus {arg}",
    "mouse": "{arg}",
    "workspace": "Goto workspace {arg}",
    "togglespecialworkspace": "Toggle special:{arg}", # (⭫⭭)
    "movetoworkspace": "Move to workspace {arg}",
    "movetoworkspacesilent": "Send to {arg}", # (⭫ 🗖 □ ■ ❏)
}


KEYS = {
    "backspace": "ʙꜱᴘ", # ⌫🠴⟨ʙᴋꜱᴘ]❬⨯⎸
    "delete": "ᴅᴇʟ", # ⌦🠶[ᴅᴇʟ⟩🅳🅴🅻🄳🄴🄻🆥🅇␡❘⨯❭|x⟩🆇🅇⎹⨯❭
    "enter": "↵", # ⏎ ↵ ↲ ↩ ⮠ ⌤ ⎆
    "equal": "=",
    "escape": "⎋", # ⎋ [ᴇꜱᴄ] 🄴🅂🄲 ␛
    "down": "▼", # ▾▼🡓
    "up": "▲", # ▴▲🡑
    "left": "◀", # ◂◀🡐
    "right": "▶", # ▸▶🡒
    "end":  "⤓", # ⤓ ▼\u0333 |⇶|
    "home": "⤒", # ⤒ ⌂ ⌅ ⌆ ▲\u033F "|⬱|
    "next": "↧", # ⇟ ▼\u0332 |⇉|
    "prior": "↥", # ⇞ ▲\u0305 |⇇|
    "mouse:272": "˙🖰",
    "mouse:273": "🖰˙",
    "mouse_up": "🖰⭫", # ⮤⮥ ⭫
    "mouse_down": "🖰⭭", # ⮦⮧ ⭭
    "period": ".",
    "space": "⎵", # ␣_⎵ [ꜱᴘᴄ] [␠]
    "super_l": "", # MODS[MAIN_INDEX][0],
    "tab": "⎹⮀⎸", # ⭾⮆tab⇥⎹⮀⎸⮀⎹⇉⎸⇄ ⇆ ⇶ ↦ ↤ ⇤ ↹ 🡒 ⏤▶⎸[␉]
    "xf86audioraisevolume": "🕪 ", # >1sp so extra sp  🕪 🠙🕨 （🕨 ⭫🕨
    "xf86audiolowervolume": "🕩 ", # 🕩 🠗🕨 （🕨 ⭭🕨
    "xf86audiomute": "×🕨", # ×🕨
    "xf86audiomicmute": "ˣ🎙",
    "xf86audionext": "⏭", # ►►⎸⏭
    "xf86audioprev": "⏮", # ⏮ ⎹◄◄
    "xf86audioplay": "►", # ⏵ ⏯ ►⏸
    "xf86audiopause": "⏸",
    "xf86monbrightnessup": "🖵 ⭫", # >1sp 💡🔥🔆\u200B ☼🠙🗤○☉⚞🗦⚬🗧⚟🖵 [|🡅⭫
    "xf86monbrightnessdown": "🖵 ⭭", # >1sp 💡🔥🔅\u200B ☀🠗🗦[🗦|🡇☀⭭
    "xf86search": "🔍\u200B", # 🔍=2wsp \u0007=del \u200B=0wsp ⌕=phone rec
}


KEYS_DESC = {
    KEYS["backspace"]: "Backspace",
    KEYS["delete"]: "Delete",
    KEYS["escape"]: "Escape",
    KEYS["space"]: "Spacebar",
    KEYS["tab"]: "Tab",
    KEYS["up"]: "Up",
    KEYS["down"]: "Down",
    KEYS["left"]: "Left",
    KEYS["right"]: "Right",
    KEYS["prior"]: "Pgup",
    KEYS["next"]: "Pgdn",
    KEYS["home"]: "Home",
    KEYS["end"]: "End",
    KEYS["mouse:272"]: "Right click",
    KEYS["mouse:273"]: "Left click",
    KEYS["mouse_up"]: "Scroll up ",
    KEYS["mouse_down"]: "Scroll down",
    KEYS["xf86search"]: "Search",
    KEYS["xf86audioraisevolume"]: "Raise volume",
    KEYS["xf86audiolowervolume"]: "Lower volume",
    KEYS["xf86audiomute"]: "Mute volume",
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
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.longest = 0
    def write(self, s, /) -> int:
        length = len(s) - escape_length(s) - s.count("\n")
        self.longest = max(self.longest, length)
        return super().write(s)
    def close(self):
        self.longest = 0
        super().close()
    def metrics(self) -> tuple[str, int]:
        """Returns (value, longest length)"""
        return (super().getvalue(), self.longest)

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

def format_bind(*, key: str = "", modmask: int = 0, sep: str = " ",
                ns: tuple = (" ", "🗦", "⎹", "［", "（", "˙"), **_) -> str:
    """
    Makes a key-binding string from a mask and a keyboard key properties in
    the json row. Some characters (bad) in key strings don't look good with
    with spaces, so no space is added. Also key not displayed if key
    is in mod string, since that's confusing for users.
    """
    mods = unmask(modmask, MODS, MAIN_INDEX)
    m = sep.join(mods)
    k = sub(key, KEYS)
    if not m:
        # So K instead of sepK
        return k
    if not k: #k in m:
        # So M instead of Msep
        return m
    if sep == " " and k.startswith(ns):
        # Don't add sep for problematic chars
        sep = ""
    # Default
    return f"{m}{sep}{k}"


def format_desc(*, arg: str = "", description: str = "",
                 dispatcher: str = "", **_) -> str:
    """Makes a description string from properties in the json row."""
    a = sub(arg, ARGS)
    disp = sub(dispatcher, DISPATCHERS)
    return disp.format(arg=a, description=description).strip()

def print_bind(row: dict, layout: str = "{} {}", sep: str = " "):
    """Prints a row from the json."""
    desc = row["description"]

    #Interpret directives in description
    if desc.startswith("!skip"):
        # E.G. !skip
        return None
    if desc.startswith("!br"):
        # E.G. !br Description
        desc = desc.removeprefix("!br").strip()
        print()
    if desc.startswith("!h"):
        # E.G. !H Heading: Description
        descs = desc.removeprefix("!h").split(":", maxsplit=1)
        print_heading(descs[0].strip(), 2, pre="\n")
        desc = descs[-1].strip()

    row["description"] = desc
    b = format_bind(**row, sep=sep)
    d = format_desc(**row)
    s = layout.format(b, d)
    print(s)
    return None


def print_cols(text: str, width: int = 24, max_width = 80, *,
               pre: str = "", end: str = ""):
    """
    Prints a lines of text in newspaperilike columns. Before the text
    is pre, and after is end (then a new line).
    """
    cols = max_width // width
    lines = text.splitlines()
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
            out += f"{pre}{line:{total_width}}{end}"
        print(out)


def print_heading(line: str, n = 1, pre: str = ""):
    """Prints a header of important N in color!"""
    print(f"{pre}{HC[n]}{line}:{HC[0]}")


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
    args = cli()
    desc_w = args.desc_width
    bind_w = max(args.bind_width - 1, 0) # because extra space in layout
    layout = f"{{:{bind_w}}} {{:{desc_w}}}"

    if args.key:
        print_heading("Key symbols", pre="\n")
        with StringIOMetrics() as buf, redirect_stdout(buf):
            print_heading("Modifier keys", 2)
            for kb, d in MODS_LIST.items():
                print(layout.format(kb, d))
            print_heading("Others on Keyboard", 2, pre="\n")
            for kb, d in KEYS_DESC.items():
                print(layout.format(kb, d))
            lines, width = buf.metrics()
        print_cols(lines, width + args.spacing, args.width)

    if not args.hide:
        print_heading("Key-bindings", pre="\n")
        with StringIOMetrics() as buf, redirect_stdout(buf):
            json.load(sys.stdin,
                      object_hook=lambda b: print_bind(b, layout))
            lines, width = buf.metrics()
        print_cols(lines, width + args.spacing, args.width)

    return 0


if __name__ == '__main__':
    sys.exit(main())
