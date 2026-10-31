#!/usr/bin/env bash
# Test for ingest-close against a fake herdr: no real pane, no risk.
# ingest-close launches `pane-close-later` detached: the test waits for it and then looks
# at the result on the fake (pane closed) and in the log under TMPDIR.
# Usage: ./ingest-close.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HERE/ingest-close"
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/ic-test.XXXXXX")"
export TMPDIR="$TMPROOT/tmp"
mkdir -p "$TMPDIR"
PANE="w8:pT01"
SAN="$(printf '%s' "$PANE" | tr -c 'A-Za-z0-9._-' '_')"
T="${TMPDIR:-/tmp}"; T="${T%/}"
LOGFILE="$T/pane-close-later-$SAN.log"
LOCK="$T/pane-close-later-$SAN.pid"
OUTLOG="$T/pane-close-later.log"
pass=0
fail=0

ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

trap 'rm -rf "$TMPROOT"; rm -f "$LOGFILE" "$LOCK"' EXIT

FAKE="$TMPROOT/fake"
mkdir -p "$FAKE"
cat > "$FAKE/herdr" <<'FAKEH'
#!/usr/bin/env bash
d="$(dirname "$0")"
sub="$1 $2"
case "$sub" in
  "pane current")
    [ -s "$d/current" ] || { echo '{"error":{"code":"no_pane"}}'; exit 0; }
    printf '{"id":"cli:pane:current","result":{"pane":{"pane_id":"%s","agent_status":"idle"}}}\n' "$(cat "$d/current")"
    ;;
  "pane get")
    printf '{"id":"cli:pane:get","result":{"pane":{"pane_id":"%s","agent_status":"idle"}}}\n' "$3"
    ;;
  "pane report-metadata") echo "$*" >> "$d/meta" ;;
  "pane close") echo "$3" >> "$d/closed" ;;
  *) echo "fake herdr: unexpected command: $*" >&2; exit 2 ;;
esac
FAKEH
chmod +x "$FAKE/herdr"
echo "$PANE" > "$FAKE/current"
: > "$FAKE/closed"
: > "$FAKE/meta"
rm -f "$LOGFILE" "$LOCK"

echo "ingest-close: test"

# 1. launches detached, does not hang, and says what it scheduled
out="$(PANE_CLOSE_HERDR="$FAKE/herdr" bash "$TARGET" 2 2>&1)"
rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 and returns at once" || { ko "exit 0 and returns at once"; printf '       %s\n' "$out"; }
printf '%s' "$out" | grep "2s of quiet" >/dev/null && ok "announces the seconds" || ko "announces the seconds"
printf '%s' "$out" | grep "title of $PANE" >/dev/null && ok "announces the pane and the title" || ko "announces the pane and the title"
printf '%s' "$out" | grep "ingest-log" >/dev/null && ko "no log for a pane that does not exist" || ok "no log for a pane that does not exist"

# 2. after the quiet period: closes the pane, once, and the countdown is in the log
deadline=$((SECONDS + 12))
while [ "$SECONDS" -lt "$deadline" ]; do
  [ -s "$FAKE/closed" ] && break
  sleep 1
done
[ "$(tr '\n' ' ' < "$FAKE/closed")" = "$PANE " ] && ok "closes the pane, and only that one" \
  || { ko "closes the pane, and only that one"; printf '       got: %s\n' "$(tr '\n' ' ' < "$FAKE/closed")"; }
grep -q 'Pane closing in: 2s' "$LOGFILE" 2>/dev/null && ok "countdown in the log" \
  || { ko "countdown in the log"; sed -n '1,10p' "$LOGFILE" 2>/dev/null; }
grep -q -- '--title' "$FAKE/meta" 2>/dev/null && ok "countdown in the pane title" || ko "countdown in the pane title"
IFS= read -r last < <(tail -1 "$LOGFILE" 2>/dev/null)
case "$last" in
  *"closing $PANE"*) ok "last line: closes the agent pane" ;;
  *) ko "last line: closes the agent pane"; printf '       last: %s\n' "$last" ;;
esac
grep -q -- '->' "$LOGFILE" 2>/dev/null && ko "no arrow in the countdown" || ok "no arrow in the countdown"

# 3. second launch: the first lock is gone, so it can be scheduled again
: > "$FAKE/closed"
out2="$(PANE_CLOSE_HERDR="$FAKE/herdr" bash "$TARGET" 1 2>&1)"
printf '%s' "$out2" | grep 'scheduled:' >/dev/null && ok "can be scheduled again after closing" || ko "can be scheduled again after closing"

# 4. arguments: non-numeric seconds -> exit 2; unresolved pane -> exit 1, nothing scheduled
PANE_CLOSE_HERDR="$FAKE/herdr" bash "$TARGET" ten >/dev/null 2>&1
[ $? -eq 2 ] && ok "non-numeric seconds: exit 2" || ko "non-numeric seconds: exit 2"
rm -f "$FAKE/current"
unset HERDR_PANE_ID
rm -f "$LOCK"
PANE_CLOSE_HERDR="$FAKE/herdr" bash "$TARGET" >/dev/null 2>&1
[ $? -eq 1 ] && ok "unresolved pane: exit 1" || ko "unresolved pane: exit 1"
sleep 1
[ -e "$LOCK" ] && ko "unresolved pane: nothing scheduled" || ok "unresolved pane: nothing scheduled"

echo ""
printf '%d ok, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
