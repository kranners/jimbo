#!/usr/bin/env bash
# Runs the change probe end to end without spike: a local bare repository stands in for
# butler-memory, a scratch change folder for butler's, and plain bash for the sandbox.
# Usage: dry-run.sh   (needs git and python3; run from anywhere)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'kill "$poller" 2>/dev/null || true; rm -rf "$work"' EXIT

fix=20261103-201700-4242
git init --quiet --bare "$work/remote.git"
mkdir -p "$work/self-fix"/{sessions,watch,archive,archived,dismissed}
echo "Started https://claude.ai/code/session_dryrun on .claude" > "$work/self-fix/sessions/$fix"
touch "$work/self-fix/watch/$fix"
python3 -c 'import secrets; print(secrets.token_hex(32))' > "$work/master"

export PROBE_STATE=$work/runner PROBE_SELF_FIX=$work/self-fix PROBE_KEY_FILE=$work/master \
  PROBE_REMOTE=$work/remote.git PROBE_RUN='["timeout", "55", "bash"]'
export SPIKE_PROBE_CONFIG=$work/client/config SPIKE_PROBE_REMOTE=$work/remote.git \
  SPIKE_PROBE_CACHE=$work/client SPIKE_PROBE_WAIT=30

( while true; do python3 "$here/runner.py" poll; sleep 2; done ) > "$work/runner.out" 2>&1 &
poller=$!

python3 "$here/spike-probe" init "$fix" "$(python3 "$here/runner.py" key "$fix")"

echo "== a signed request runs and its output comes back"
out=$(echo 'echo hello from $(whoami); exit 3' | python3 "$here/spike-probe")
echo "$out"
grep -q "hello from" <<< "$out"
grep -q "spike-probe #1 for change $fix" <<< "$out"

echo "== a second request gets the next number"
out=$(echo 'echo second' | python3 "$here/spike-probe")
grep -q "spike-probe #2" <<< "$out" && grep -q second <<< "$out"

echo "== a request signed with the wrong key is refused, not run"
python3 "$here/spike-probe" init "$fix" "$(printf '0%.0s' {1..64})"
out=$(echo 'touch '"$work"'/should-not-exist' | python3 "$here/spike-probe")
echo "$out"
grep -q "signature does not match" <<< "$out"
[ ! -e "$work/should-not-exist" ]

echo "== once the fix ends, nothing more runs"
python3 "$here/spike-probe" init "$fix" "$(python3 "$here/runner.py" key "$fix")"
touch "$work/self-fix/archived/$fix"
if echo 'echo too late' | SPIKE_PROBE_WAIT=15 python3 "$here/spike-probe"; then
  echo "FAIL: an ended fix still ran a request" >&2
  exit 1
fi

echo "== every request was logged"
cat "$work/runner/log.jsonl"
[ "$(wc -l < "$work/runner/log.jsonl")" -eq 3 ]
echo "dry run passed"
