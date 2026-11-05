

# A fixture-driven test of butler-work's snapshot, appended after builders.py and work.py without their mains.
# It runs offline, so GitHub answers nothing and only the records on disk count.


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)


def test(out):
    global SELF_FIX, LIMITS_DIR, STATE
    root = tempfile.mkdtemp()
    SELF_FIX = os.path.join(root, 'self-fix')
    LIMITS_DIR = os.path.join(root, 'limits')
    STATE = os.path.join(root, 'cache')
    os.makedirs(STATE)
    now = time.time()
    stamp = time.strftime('%Y%m%d-%H%M%S', time.localtime(now - 3600))
    working, waiting, landed, queued = (stamp + '-1', stamp + '-2', stamp + '-3', stamp + '-4')
    link = 'https://claude.ai/code/session_ABC123'
    secret = 'ghp_' + 'a' * 30
    write(os.path.join(SELF_FIX, 'sessions', working), 'Started %s\n' % link)
    write(os.path.join(SELF_FIX, 'progress', working),
          'State: running\nTitle: Kanban <b>board</b> messages\nLast activity: 2026-11-03T11:00:00Z\n'
          'Branch: https://github.com/kranners/jimbo claude/kanban-x\n')
    write(os.path.join(SELF_FIX, 'briefs', working),
          'Aaron\'s request (3 Nov 2026, 21:35, on a call), in his words: "Let me message Butler from the board." '
          'He wants the board\'s popup to message Butler from modules/hosts/spike/butler-kanban.nix, token %s.\n\nMore detail.' % secret)
    write(os.path.join(SELF_FIX, 'sessions', waiting), 'Started %s\n' % link)
    write(os.path.join(SELF_FIX, 'progress', waiting),
          'State: waiting on input (Bash)\nTitle: iPad remote desk\nLast activity: 2026-11-03T11:10:00Z\n')
    write(os.path.join(SELF_FIX, 'briefs', waiting),
          'Aaron\'s request, in his words: "Let me use my Macs from the iPad. See %s."' % working)
    write(os.path.join(SELF_FIX, 'sessions', landed), 'Started %s\n' % link)
    write(os.path.join(SELF_FIX, 'progress', landed),
          'State: finished\nTitle: Self-fix call speech truncation\nLast activity: %s\n'
          'Final summary: Butler now finishes long replies on calls. Changed: call replies Before: cut off After: finished whole '
          'Ready: long answers on calls Go live: within 5 minutes Aaron must: run the script on the PC Commit: jimbo 06acaa7\n'
          % time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now - 600)))
    write(os.path.join(SELF_FIX, 'queue', queued + '.json'), json.dumps({'request': 'Aaron\'s request, in his words: "Show the work."'}))
    write(os.path.join(LIMITS_DIR, 'claude-limits-work.prom'),
          'claude_limit_percent{account="work",kind="session",model=""} 12\n'
          'claude_limit_percent{account="work",kind="weekly_all",model=""} 65\n'
          'claude_limit_resets_at_seconds{account="work",kind="weekly_all",model=""} 1762300000\n'
          'claude_limit_percent{account="work",kind="weekly_scoped",model="Fable"} 3\n')
    write(os.path.join(LIMITS_DIR, 'claude-limits-personal.prom'),
          'claude_limit_percent{account="personal",kind="weekly_all",model=""} 21\n')

    snapshot = work_snapshot(GitHub(), now)
    text = json.dumps(snapshot)
    by_id = {c['id']: c for c in snapshot['changes']}

    assert secret not in text, 'a token reached the snapshot'
    assert 'modules/hosts' not in text and 'claude/kanban-x' not in text, 'a path or branch reached the snapshot'
    assert 'More detail' not in text, 'brief text past the first paragraph reached the snapshot'
    assert by_id[working]['kind'] == 'working' and 'The kanban board' in by_id[working]['areas']
    assert by_id[working]['purpose'].startswith('You want the board'), by_id[working]['purpose']
    assert by_id[waiting]['kind'] == 'waiting' and by_id[waiting]['need']['action'] == 'Approve a step'
    assert 'The iPad and iPhone apps' in by_id[waiting]['areas'] and 'Your machines' in by_id[waiting]['areas']
    assert by_id[landed]['kind'] == 'landed' and by_id[landed]['title'] == 'Change call speech truncation', by_id[landed]['title']
    assert by_id[landed]['changed'] == 'finished whole' and 'within 5 minutes' in by_id[landed]['notice']
    assert by_id[landed]['need']['action'] == 'Do a hand step' and 'The call voice' in by_id[landed]['areas']
    assert by_id[queued]['kind'] == 'queued'
    assert [n['id'] for n in snapshot['needs']] == [waiting, landed], snapshot['needs']
    assert snapshot['counts'] == {'running': 2, 'waiting': 2, 'landed_today': 1, 'live': 3}, snapshot['counts']
    assert snapshot['next']['id'] == working
    assert any(e['kind'] == 'builds on' and e['from'] == waiting and e['to'] == working for e in snapshot['edges'])
    assert snapshot['usage'][0]['account'] == 'personal' and snapshot['usage'][1]['weekly'] == 65 and snapshot['usage'][1]['session'] == 12
    with open(out, 'w') as f:
        json.dump(snapshot, f, indent=1, ensure_ascii=False)
    print('butler-work test: ok, %d changes' % len(snapshot['changes']))


if __name__ == '__main__':
    test(sys.argv[1])
