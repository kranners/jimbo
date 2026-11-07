"""mac key's combo parser; run as python3 test_keys.py keys.py, with vncdotool importable to check the key table."""
import importlib.util
import sys

spec = importlib.util.spec_from_file_location('keys', sys.argv[1])
k = importlib.util.module_from_spec(spec)
spec.loader.exec_module(k)

failures = []


def expect(combo, wanted, system='macos'):
    try:
        got = k.key_combo(combo, system)
    except k.KeyRefused as error:
        got = 'refused: %s' % error
    if got != wanted:
        failures.append('%s on %s: wanted %r, got %r' % (combo, system, wanted, got))


def refused(combo, words, system='macos'):
    try:
        got = k.key_combo(combo, system)
        failures.append('%s on %s: wanted a refusal naming %r, got %r' % (combo, system, words, got))
    except k.KeyRefused as error:
        if words not in str(error):
            failures.append('%s on %s: refusal %r does not name %r' % (combo, system, str(error), words))


# The desk session's own combo, both separators, and case as menus write it.
for combo in ('cmd+k', 'cmd-k', 'Cmd+K', 'CMD-k', 'command+k', 'super+k'):
    expect(combo, 'super-k')
expect('cmd+l', 'super-l')
expect('cmd+t', 'super-t')
expect('cmd+w', 'super-w')
expect('cmd+q', 'super-q')
expect('cmd+shift+4', 'super-shift-4')
expect('shift+cmd+4', 'shift-super-4')
expect('cmd-shift-t', 'super-shift-t')
expect('cmd+option+i', 'super-alt-i')
expect('opt-left', 'alt-left')
expect('ctrl+alt+t', 'ctrl-alt-t', 'linux')
expect('control-tab', 'ctrl-tab')
expect('cmd+shift+]', 'super-shift-]')
expect('cmd-shift-[', 'super-shift-[')
expect('cmd+,', 'super-,')
expect('cmd+.', 'super-.')
expect('cmd+/', 'super-/')
expect('cmd+`', 'super-`')
expect('cmd+=', 'super-=')
expect('cmd++', 'super-+')
expect('cmd+plus', 'super-+')
expect('cmd+-', 'super-minus')
expect('cmd--', 'super-minus')
expect('cmd+minus', 'super-minus')
expect('-', 'minus')
expect('+', '+')
expect('cmd-1', 'super-1')
expect('cmd+space', 'super-space')
expect('return', 'enter')
expect('Enter', 'enter')
expect('escape', 'esc')
expect('tab', 'tab')
expect('shift+tab', 'shift-tab')
expect('cmd+delete', 'super-bsp')
expect('delete', 'bsp')
expect('delete', 'del', 'linux')
expect('backspace', 'bsp', 'windows')
expect('forwarddelete', 'del')
expect('pageup', 'pgup')
expect('ctrl+up', 'ctrl-up')
expect('cmd+ctrl+f', 'super-ctrl-f')
expect('shift', 'shift')
expect('cmd-cmd-k', 'super-k')
expect('K', 'K')
expect('k', 'k')
expect('super+1', 'super-1', 'linux')
expect('win+e', 'super-e', 'windows')
expect('ctrl+shift+v', 'ctrl-shift-v', 'linux')
expect('ctrl+shift+t', 'ctrl-shift-t', 'windows')

# Function keys, never.
for combo in ('f1', 'F5', 'f12', 'cmd+f3', 'alt-f4', 'fn', 'ctrl+alt+f2', 'f20'):
    refused(combo, 'function key', 'linux' if combo == 'ctrl+alt+f2' else 'macos')
refused('alt+f4', 'function key', 'windows')
# Cmd on the PC.
refused('cmd+c', 'no cmd key', 'linux')
refused('cmd-c', 'no cmd key', 'windows')
# Dangerous chords, with why and what instead.
refused('cmd+option+esc', 'Force Quit')
refused('cmd+alt+escape', 'instead: quit only an app you opened')
refused('ctrl+cmd+q', 'locks the screen')
refused('cmd+shift+q', 'logs Aaron out')
refused('cmd+option+shift+q', 'logs Aaron out')
refused('super+shift+q', 'Hyprland', 'linux')
refused('ctrl+alt+delete', 'reboots', 'linux')
refused('ctrl+alt+backspace', 'graphical session', 'linux')
refused('win+l', 'locks the PC', 'windows')
refused('ctrl+alt+del', 'secure screen', 'windows')
# Nonsense and system keys.
refused('cmd+kk', 'unknown key kk')
refused('cmd+', 'unknown key')
refused('', 'empty combo')
refused('cmd+k+l', 'pass each as its own combo')
refused('power', 'system or media key')
refused('cmd+eject', 'system or media key')
refused('cmd+é', 'unknown key')
# cmd+l is fine on Linux and Windows' super+l is only refused on Windows.
expect('super+l', 'super-l', 'linux')
expect('ctrl+l', 'ctrl-l', 'windows')

# Self-check of the key table: every keysym name the parser can produce is one vncdotool knows.
try:
    from vncdotool import client as vnc
except ImportError:
    vnc = None
if vnc is not None:
    missing = [name for name in k.KEY_KEYSYMS if name not in vnc.KEYMAP]
    if missing:
        failures.append('vncdotool has no keysym for %s' % ', '.join(missing))
    for name in sorted(set(k.KEY_NAMES) | set(k.KEY_MODIFIERS) | set(k.KEY_CHARACTERS)):
        for system in ('macos', 'linux', 'windows'):
            if system != 'macos' and name in ('cmd', 'command'):
                continue
            for part in k.key_combo(name, system).split('-'):
                if part != 'minus' and len(part) != 1 and part not in vnc.KEYMAP:
                    failures.append('%s on %s gives %s, which vncdotool does not know' % (name, system, part))
elif '--require-vncdotool' in sys.argv:
    failures.append('vncdotool is not importable, so the key table was not checked')

if failures:
    print('\n'.join(failures))
    sys.exit(1)
print('ok: key combos parse, refuse and map to vncdotool keysyms')
