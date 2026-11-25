# SPDX-License-Identifier: GPL-3.0-or-later
"""Generic keyboard policy copied from the fixed Meridiana snapshot."""

MODIFIERS = ("Meta", "Ctrl", "Alt", "Shift")
ALTGR = set("[]{}@#~`\\")

def plain(text: str) -> str:
    """The text of a menu without the & of its access key."""
    return text.replace("&&", "\0").replace("&", "").replace("\0", "&")

def normalize(keys: str) -> str:
    """One way of writing keys: modifiers in Qt's order and capitalised, a letter in capitals. «shift+ctrl+p»
    is «Ctrl+Shift+P»; chords («Ctrl+K, Ctrl+S») each on their own."""
    return ", ".join(_chord(c) for c in keys.split(", ") if c.strip())

def _chord(chord: str) -> str:
    mods, key = _parts(chord.strip())
    key = key.strip()
    key = key.upper() if len(key) == 1 else {"delete": "Del", "escape": "Esc", "enter": "Return"}.get(
        key.lower(), key[:1].upper() + key[1:])
    return "+".join([m for m in MODIFIERS if m in mods] + [key])

def _mod(text: str) -> str:
    return {"ctrl": "Ctrl", "control": "Ctrl", "shift": "Shift", "alt": "Alt", "meta": "Meta", "super": "Meta",
            "win": "Meta"}.get(text.strip().lower(), "")

def _parts(chord: str) -> tuple[set, str]:
    """The modifiers and the key of one chord; «Ctrl++» has the plus as its key."""
    if chord.endswith("++") or chord == "+":
        head, key = chord[:-2] if chord != "+" else "", "+"
    elif "+" in chord:
        head, _plus, key = chord.rpartition("+")
    else:
        head, key = "", chord
    return {m for m in (_mod(p) for p in head.split("+")) if m}, key

def problem(keys: str, translate=str) -> str:
    """Why these keys should not start a command (study 12a, 1.9 and 1.11), or ""."""
    for chord in normalize(keys).split(", "):
        mods, key = _parts(chord)
        if "Meta" in mods:
            return translate("The Super (Windows) key belongs to the system and to Niri")
        if {"Ctrl", "Alt"} <= mods:
            return translate("Ctrl+Alt is AltGr on an Italian keyboard: Ctrl+Alt+E writes €")
        if "Alt" in mods and (len(key) == 1 and key.isalnum()):
            return translate("Alt with a letter or a digit opens the menus")
        if key in ALTGR:
            return translate("«{key}» is written with AltGr on an Italian keyboard").format(key=key)
        if key == "?" and "Shift" in mods:
            return translate("Shift+? needs Shift twice on an Italian keyboard")
        if key == "/" and {"Ctrl", "Shift"} <= mods:
            return translate("Ctrl+Shift+/ needs Shift twice on an Italian keyboard")
        if key == "Space" and "Ctrl" in mods:
            return translate("Ctrl+Space switches the input method on some systems")
        if key == "U" and {"Ctrl", "Shift"} <= mods:
            return translate("Ctrl+Shift+U types a Unicode character on Linux")
        if mods == {"Alt"} and key == "F4":
            return translate("Alt+F4 closes the window")
    return ""

def single(keys: str) -> bool:
    """A key without modifiers that writes a character: it works only while no field is being written in."""
    mods, key = _parts(normalize(keys))
    return ", " not in normalize(keys) and not mods and len(key) == 1

def only_f_key(keys) -> bool:
    """All the keys are F keys: on a laptop without Fn lock they are media keys."""
    def f(k):
        _mods, key = _parts(normalize(k))
        return key[:1] == "F" and key[1:].isdigit()
    return bool(keys) and all(f(k) for k in keys)

def clashes(current: dict, cid: str, keys: str) -> list[str]:
    """The other commands that already answer to `keys`: they would stop working with them."""
    k = normalize(keys)
    return [other for other, ks in current.items() if other != cid and k in ks]

def conflicts(current: dict) -> dict:
    """keys -> the commands that share them, when more than one does."""
    holders: dict = {}
    for cid, ks in current.items():
        for k in ks:
            holders.setdefault(k, []).append(cid)
    return {k: ids for k, ids in holders.items() if len(ids) > 1}
