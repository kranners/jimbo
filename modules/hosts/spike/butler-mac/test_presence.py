"""Presence notes: who else is on a machine and whether Aaron is; run as python3 test_presence.py presence.py."""
import importlib.util
import sys
import tempfile

spec = importlib.util.spec_from_file_location('presence', sys.argv[1])
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)

now = 1_000_000.0
folder = tempfile.mkdtemp()

# Theo looked at pilot a minute ago in Chromium, Drive tab; the DM looks now.
p.presence_record(folder, 'pilot', 'thr-theo', {'footman': 'Theo', 'title': 'x', 'app': 'Chromium', 'window': 'Drive tab', 'action': 'mac pilot click'}, now - 60)
data = p.presence_record(folder, 'pilot', 'dm', {'title': 'the DM', 'app': 'Finder'}, now)
lines = p.presence_lines(data, 'dm', 'pilot', now)
assert lines == ['Theo is in Chromium on pilot, Drive tab, 1 min ago (mac pilot click).'], lines

# The footman does not hear of himself, and an old sighting is dropped.
assert p.presence_lines(data, 'thr-theo', 'pilot', now) == ['Thread "the DM" is in Finder on pilot, just now.']
assert p.presence_lines(data, 'dm', 'pilot', now + p.PRESENCE_MS + 61) == []

# Aaron: recent input that is not butler's own.
assert p.aaron_active(5, now - 60, now) is True
assert p.aaron_active(5, now - 2, now) is False, "butler's own click a moment ago"
assert p.aaron_active(25, now - 60, now) is False
assert p.aaron_active(None, 0, now) is False
note = p.presence_note(lines, True, 5, 'pilot')
assert 'Aaron is using this Mac right now' in note and 'nothing is locked' in note, note
assert p.presence_note([], False, None, 'pilot') == ''
print('presence: ok')
