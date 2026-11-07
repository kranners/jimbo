# mac <host> key: turns a combo such as cmd+k, cmd-shift-4 or ctrl+alt+t into the dash-joined keysym names vncdotool's
# keyPress takes, or refuses it saying why and what to use instead. A combo joins its keys with + or -, case aside, its
# modifiers in any order and one other key last, or a lone modifier. Function keys are never sent, since on 3 Nov 2026
# one reached the front app's hardware keys rather than the Mac, nor chords that lock the screen, log Aaron out, force
# quit apps or end his Hyprland session.
# mac.py takes this file in place of its @keys@ line, without the imports, which it already has; test_keys.py imports it.
import re


class KeyRefused(Exception):
    pass


# Every name a combo may use, to the keysym name vncdotool's KEYMAP knows; a single printable character is sent as itself.
KEY_MODIFIERS = {
    'cmd': 'super', 'command': 'super', 'super': 'super', 'win': 'super', 'windows': 'super', 'meta': 'super',
    'ctrl': 'ctrl', 'control': 'ctrl', 'alt': 'alt', 'opt': 'alt', 'option': 'alt', 'shift': 'shift',
}
KEY_NAMES = {
    'enter': 'enter', 'return': 'enter', 'tab': 'tab', 'esc': 'esc', 'escape': 'esc', 'space': 'space',
    'bsp': 'bsp', 'backspace': 'bsp', 'del': 'del', 'forwarddelete': 'del', 'fwddelete': 'del',
    'home': 'home', 'end': 'end', 'pgup': 'pgup', 'pageup': 'pgup', 'pgdn': 'pgdn', 'pagedown': 'pgdn',
    'left': 'left', 'right': 'right', 'up': 'up', 'down': 'down', 'ins': 'ins', 'insert': 'ins',
    'minus': 'minus', 'dash': 'minus', 'hyphen': 'minus',
}
# Punctuation by name, for a shell or a reader that mangles the character itself.
KEY_CHARACTERS = {
    'plus': '+', 'equal': '=', 'equals': '=', 'comma': ',', 'period': '.', 'dot': '.', 'slash': '/',
    'backslash': '\\', 'semicolon': ';', 'quote': "'", 'apostrophe': "'", 'backtick': '`', 'grave': '`',
    'lbracket': '[', 'bracketleft': '[', 'rbracket': ']', 'bracketright': ']',
}
# The keysym names key_combo may hand vncdotool, which test_keys.py checks its KEYMAP has; minus mac.py adds itself.
KEY_KEYSYMS = sorted(set(KEY_MODIFIERS.values()) | set(KEY_NAMES.values()) - {'minus'})
FUNCTION_KEY = re.compile(r'^(?:f\d{1,2}|fn|function)$')
# Keys with no business on these machines: the media and power keys, the lock and system keys.
OTHER_KEYS = {'power', 'eject', 'sleep', 'caplk', 'capslock', 'numlock', 'scrlk', 'sysrq', 'prtsc', 'pause', 'break', 'menu',
              'mute', 'volumeup', 'volumedown', 'brightnessup', 'brightnessdown', 'play', 'next', 'previous', 'hyper'}
KEY_SYSTEMS = {'macos': 'macOS', 'linux': 'Linux', 'windows': 'Windows'}
# Chords refused on each system, by their keys, with why and what to do instead.
DANGEROUS_CHORDS = {
    'macos': [
        ({'super', 'alt', 'esc'}, 'opens Force Quit, which kills apps without saving', 'quit only an app you opened: open -a it, look, then key cmd+q'),
        ({'super', 'alt', 'shift', 'esc'}, 'force quits the front app without saving', 'quit only an app you opened: open -a it, look, then key cmd+q'),
        ({'ctrl', 'super', 'q'}, 'locks the screen, which only Aaron can unlock', 'leave the Mac unlocked, or mac <host> sleep if Aaron asked for that'),
        ({'super', 'shift', 'q'}, 'logs Aaron out, closing every app', 'nothing: logging out is Aaron\'s to do'),
        ({'super', 'alt', 'shift', 'q'}, 'logs Aaron out at once, closing every app', 'nothing: logging out is Aaron\'s to do'),
        ({'ctrl', 'super', 'shift', 'q'}, 'locks the screen', 'leave the Mac unlocked'),
    ],
    'linux': [
        ({'super', 'shift', 'q'}, 'closes the front window and ends the Hyprland session once none is left', 'close a window you opened from its own menu or with ctrl+w'),
        ({'ctrl', 'alt', 'del'}, 'reboots or logs out', 'nothing: restarting is Aaron\'s to do, or mac jimbo boot when he asks'),
        ({'ctrl', 'alt', 'bsp'}, 'kills the graphical session', 'nothing'),
    ],
    'windows': [
        ({'ctrl', 'alt', 'del'}, 'opens the secure screen, which VNC cannot drive', 'nothing: that screen is Aaron\'s'),
        ({'super', 'l'}, 'locks the PC, which only Aaron can unlock', 'leave it unlocked, or mac jimbo sleep if Aaron asked for that'),
        ({'ctrl', 'shift', 'esc'}, 'opens Task Manager, which kills apps', 'quit only an app you opened, from its own window'),
    ],
}


def key_split(combo, separator):
    if combo == separator:
        return [separator]
    if combo.endswith(separator * 2):
        return combo[:-2].split(separator) + [separator]
    return combo.split(separator)


def key_token(token, system):
    """One key of a combo as ('modifier'|'key', keysym name, canonical name), or None when it is not a key."""
    lower = token.lower()
    if lower in KEY_MODIFIERS:
        return 'modifier', KEY_MODIFIERS[lower], KEY_MODIFIERS[lower]
    if lower == 'delete':
        # Delete is backspace on a Mac's keyboard and the forward delete key on a PC's.
        name = 'bsp' if system == 'macos' else 'del'
        return 'key', name, name
    if lower in KEY_NAMES:
        return 'key', KEY_NAMES[lower], KEY_NAMES[lower]
    character = KEY_CHARACTERS.get(lower, token if len(token) == 1 else None)
    if character is None or not (' ' < character <= '~'):
        return None
    if character == '-':
        return 'key', 'minus', '-'
    return 'key', character.lower(), character.lower()


def key_refuse_reason(token):
    lower = token.lower()
    if FUNCTION_KEY.match(lower):
        return ('%s is a function key, which mac never sends: on 3 Nov 2026 one reached the front app\'s hardware keys. '
                'Choose the item from the app\'s menu with mac <host> menu front, or use its ordinary shortcut' % token)
    if lower in OTHER_KEYS:
        return '%s is a system or media key, which mac never sends' % token
    return None


def key_combo(combo, system='macos'):
    """The vncdotool keysym string for combo on system, such as super-k for cmd+k, or KeyRefused saying why not."""
    if not combo:
        raise KeyRefused('an empty combo: give keys such as cmd+k, cmd+shift+4, ctrl+alt+t or enter')
    candidates = [key_split(combo, '-'), key_split(combo, '+')]
    if '+' in combo and '-' in combo:
        candidates.append(re.split(r'(?<=.)[-+](?=.)', combo))
    best = None
    for tokens in candidates:
        if '' in tokens:
            continue
        for token in tokens:
            reason = key_refuse_reason(token)
            if reason:
                raise KeyRefused(reason)
        parsed = [key_token(token, system) for token in tokens]
        if None not in parsed:
            best = (tokens, parsed)
            break
        if best is None or len(tokens) > len(best[0]):
            best = (tokens, None)
    if best is None or best[1] is None:
        unknown = [token for token in (best[0] if best else [combo]) if key_token(token, system) is None]
        raise KeyRefused('unknown key %s in %s: use cmd (or command), ctrl, alt (or option) and shift, joined with + or -, '
                         'then one key such as a letter, digit, punctuation, enter, tab, esc, space, delete, the arrows, home, end, pgup or pgdn, '
                         'as in cmd+k, cmd+shift+4 or ctrl+alt+t' % (', '.join(unknown) or combo, combo))
    tokens, parsed = best
    modifiers = [p for p in parsed if p[0] == 'modifier']
    others = [p for p in parsed if p[0] == 'key']
    if len(others) > 1:
        raise KeyRefused('%s presses %d keys besides modifiers; pass each as its own combo, such as key cmd+k enter' % (combo, len(others)))
    if system != 'macos' and any(token.lower() in ('cmd', 'command') for token in tokens):
        raise KeyRefused('%s has no cmd key: use ctrl for shortcuts such as ctrl+c, and super for the Windows or Hyprland key' % KEY_SYSTEMS[system])
    held = []
    for _, name, _ in modifiers:
        if name not in held:
            held.append(name)
    chord = set(held) | {p[2] for p in others}
    for refused, why, instead in DANGEROUS_CHORDS.get(system, []):
        if chord == refused:
            raise KeyRefused('on %s, %s %s, so mac never sends it; instead: %s' % (KEY_SYSTEMS[system], combo, why, instead))
    names = [p[1] for p in others]
    if not held and len(tokens[-1]) == 1 and tokens[-1].isalpha():
        # A lone letter keeps its case, so key K types a capital; with a modifier, cmd+K is cmd+k, as menus write it.
        names = [tokens[-1]]
    return '-'.join(held + names)
