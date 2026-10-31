#!/usr/bin/env bash
# Test for pane-close-later against a fake herdr: no real pane, no risk.
# Usage: ./pane-close-later.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HERE/pane-close-later"
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/pcl-test.XXXXXX")"
export TMPDIR="$TMPROOT/tmp"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPROOT"; rm -f "${TMPDIR:-/tmp}"/pane-close-later-w5_pT*' EXIT
pass=0
fail=0
n=0

ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# fake herdr: `pane get` consumes one line from status_file and repeats the last one once
# exhausted; `pane close` writes the pane to close_file; `pane current` answers the pane_id
# from current_file.
make_fake() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/herdr" <<'FAKE'
#!/usr/bin/env bash
d="$(dirname "$0")"
sub="$1 $2"
case "$sub" in
  "pane current")
    [ -s "$d/current" ] || { echo '{"error":{"code":"no_pane"}}'; exit 0; }
    printf '{"result":{"pane":{"pane_id":"%s","agent_status":"idle"}}}\n' "$(cat "$d/current")"
    ;;
  "pane get")
    id="$3"
    [ -n "${FAKE_SLOW:-}" ] && sleep "$FAKE_SLOW"
    if [ ! -s "$d/status" ]; then
      echo '{"error":{"code":"pane_not_found"}}'
      exit 0
    fi
    st="$(head -1 "$d/status")"
    if [ "$(grep -c '' "$d/status")" -gt 1 ]; then
      tail -n +2 "$d/status" > "$d/status.tmp" && mv "$d/status.tmp" "$d/status"
    fi
    [ "$st" = "GONE" ] && { echo '{"error":{"code":"pane_not_found"}}'; exit 0; }
    [ "$st" = "ERR" ] && { echo '{"error":{"code":"io"}}'; exit 0; }
    if [ -n "${FAKE_SPACES:-}" ]; then
      printf '{"result":{"pane":{"pane_id": "%s", "agent_status": "%s"}}}\n' "$id" "$st"
    else
      printf '{"result":{"pane":{"pane_id":"%s","agent_status":"%s"}}}\n' "$id" "$st"
    fi
    ;;
  "pane report-metadata")
    shift 2
    echo "$*" >> "$d/meta"
    ;;
  "pane process-info")
    printf '{"result":{"process_info":{"pane_id":"%s","foreground_processes":[{"pid":%s}]}}}\n' "$3" "$$"
    ;;
  "pane close")
    echo "$3" >> "$d/closed"
    ;;
  *) echo "fake herdr: unexpected command: $*" >&2; exit 2 ;;
esac
FAKE
  chmod +x "$dir/herdr"
}

# Run in the background with a timeout: returns 0 if the process is still alive after N
# seconds (what we want when the pane must NOT be closed).
run_and_kill() {
  local seconds="$1"; shift
  PANE_CLOSE_HERDR="$FAKE/herdr" "$@" &
  local pid=$!
  sleep "$seconds"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 0
  fi
  wait "$pid" 2>/dev/null
  return 1
}

# Every case gets its own pane id: pane-close-later's lock is per pane, and different cases
# must not wait for each other.
case_new() {
  n=$((n + 1))
  CASE="$TMPROOT/$1"
  FAKE="$CASE/fake"
  PANE="w5:pT$(printf '%02d' "$n")"
  make_fake "$FAKE"
  echo "$PANE" > "$FAKE/current"
  : > "$FAKE/closed"
  rm -f "${TMPDIR:-/tmp}/pane-close-later-$PANE.pid"
}

echo "pane-close-later: test"

# 1. idle pane -> closes
case_new idle
printf 'idle\nidle\nidle\nidle\n' > "$FAKE/status"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE" >/dev/null 2>&1
if [ "$(cat "$FAKE/closed")" = "$PANE" ]; then ok "idle pane: closes"; else ko "idle pane: closes"; fi

# 2. working pane -> does not close
case_new working
printf 'working\n' > "$FAKE/status"
if run_and_kill 4 env PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE"; then
  [ -s "$FAKE/closed" ] && ko "working pane: does not close" || ok "working pane: does not close"
else
  ko "working pane: does not close (process exited by itself)"
fi

# 3. pane blocked on a question -> does not close
case_new blocked
printf 'blocked\n' > "$FAKE/status"
if run_and_kill 4 env PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE"; then
  [ -s "$FAKE/closed" ] && ko "blocked pane: does not close" || ok "blocked pane: does not close"
else
  ko "blocked pane: does not close (process exited by itself)"
fi

# 4. the counter restarts: works, then stops -> closes only after the full quiet period
case_new reset
printf 'working\nworking\nworking\nidle\nidle\nidle\nidle\n' > "$FAKE/status"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE" >/dev/null 2>&1
if [ "$(cat "$FAKE/closed")" = "$PANE" ]; then ok "quiet period reset by activity: closes after"; else ko "quiet period reset by activity: closes after"; fi

# 5. pane gone mid-way -> exits without closing
case_new gone
printf 'idle\nGONE\n' > "$FAKE/status"
if run_and_kill 6 env PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 10 --poll 1 --pane "$PANE"; then
  ko "gone pane: exits"
else
  [ -s "$FAKE/closed" ] && ko "gone pane: does not close" || ok "gone pane: exits without closing"
fi

# 6. no resolvable pane -> error
case_new nopane
printf 'idle\n' > "$FAKE/status"
rm -f "$FAKE/current"
unset HERDR_PANE_ID
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 >/dev/null 2>&1
if [ $? -eq 1 ]; then ok "unresolved pane: exit 1"; else ko "unresolved pane: exit 1"; fi

# 7. two launches on the same pane -> the second exits
case_new lock
printf 'working\n' > "$FAKE/status"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 30 --poll 1 --pane "$PANE" >/dev/null 2>&1 &
first=$!
sleep 1
if PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 30 --poll 1 --pane "$PANE" >/dev/null 2>&1; then
  alive=$(ps -p "$first" -o pid= | wc -l | tr -d ' ')
  [ "$alive" = "1" ] && ok "second launch: does not disturb the first" || ko "second launch: first process disappeared"
else
  ko "second launch: exit non-zero"
fi
kill "$first" 2>/dev/null
wait "$first" 2>/dev/null
rm -f "${TMPDIR:-/tmp}/pane-close-later-$PANE.pid"

# 8. --dry-run closes nothing and writes nothing into the pane
case_new dry
printf 'idle\nidle\nidle\n' > "$FAKE/status"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE" --tty "$CASE/tty" --dry-run >/dev/null 2>&1
[ -s "$FAKE/closed" ] && ko "dry-run: does not close" || ok "dry-run: does not close"
[ -s "$CASE/tty" ] && ko "dry-run: writes nothing into the pane" || ok "dry-run: writes nothing into the pane"
[ -s "$FAKE/meta" ] && ko "dry-run: leaves the title alone" || ok "dry-run: leaves the title alone"

# 9. countdown visible on the tty: banner once, then one line per second, then close
case_new countdown
printf 'idle\nidle\nidle\nidle\nidle\n' > "$FAKE/status"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 3 --poll 1 --pane "$PANE" --tty "$CASE/tty" >/dev/null 2>&1
lines="$(tr -d '\r' < "$CASE/tty" 2>/dev/null)"
# The countdown is measured in real time, so a slow round can skip a number (3s, 1s): the
# intent is a strictly decreasing sequence that starts full, never shows 0s, ends with the
# close. Asserting the exact three lines made the suite flaky on a loaded machine.
printf '%s\n' "$lines" | head -1 | grep '\[LOG\] Ingest Completed · Pane closing in: 3s' \
  >/dev/null && ok "countdown: first line at the full idle" || { ko "countdown: first line at the full idle"; printf '       got: %s\n' "$(printf '%s' "$lines" | tr '\n' '|')"; }
[ "$(printf '%s\n' "$lines" | tail -1)" = "[LOG] Pane closing now" ] \
  && ok "countdown: ends with the closing line" || ko "countdown: ends with the closing line"
nums="$(printf '%s\n' "$lines" | sed -n 's/.*Pane closing in: \([0-9]*\)s.*/\1/p')"
count=0; prev=999; mono=1
for v in $nums; do
  count=$((count + 1))
  { [ "$v" -lt "$prev" ] && [ "$v" -ge 1 ]; } || mono=0
  prev="$v"
done
[ "$mono" -eq 1 ] && ok "countdown: strictly decreasing, never 0s" || ko "countdown: strictly decreasing, never 0s"
[ "$count" -ge 1 ] && [ "$count" -le 3 ] && ok "countdown: at most one line per second ($count)" || ko "countdown: at most one line per second ($count)"
[ "$(cat "$FAKE/closed")" = "$PANE" ] && ok "countdown: closes at the end" || ko "countdown: closes at the end"

# 10. activity in between: countdown cancelled, restarts, banner again, closes
case_new cancel
printf 'idle\nworking\nidle\nidle\nidle\n' > "$FAKE/status"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 3 --poll 1 --pane "$PANE" --tty "$CASE/tty" >/dev/null 2>&1
lines="$(tr -d '\r' < "$CASE/tty" 2>/dev/null)"
[ "$(printf '%s\n' "$lines" | grep -c 'countdown cancelled')" = "1" ] && ok "activity: countdown cancelled once" || ko "activity: countdown cancelled once"
[ "$(printf '%s\n' "$lines" | grep -c 'Pane closing in: 3s')" = "2" ] && ok "activity: countdown restarts from the top" || ko "activity: countdown restarts from the top"
[ "$(cat "$FAKE/closed")" = "$PANE" ] && ok "activity: closes after the full quiet period" || ko "activity: closes after the full quiet period"

# 11. --no-banner: no "Ingest Completed" line
case_new nobanner
printf 'idle\nidle\nidle\nidle\n' > "$FAKE/status"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE" --tty "$CASE/tty" --no-banner >/dev/null 2>&1
grep -q 'Ingest Completed' "$CASE/tty" 2>/dev/null && ko "--no-banner: no banner" || ok "--no-banner: no banner"
# 12. the countdown lives in the pane title (metadata), not in the terminal
case_new title
printf 'idle\nidle\nidle\nidle\nworking\n' > "$FAKE/status"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 3 --poll 1 --pane "$PANE" >/dev/null 2>&1
meta="$(cat "$FAKE/meta" 2>/dev/null)"
printf '%s\n' "$meta" | grep -- '--title \[LOG\] Ingest Completed · Pane closing in: 3s' \
  >/dev/null && ok "title: first tick at 3s" || ko "title: first tick at 3s"
last="$(printf '%s\n' "$meta" | sed -n 's/.*Pane closing in: \([0-9]*\)s.*/\1/p' | tail -1)"
[ -n "$last" ] && [ "$last" -ge 1 ] && [ "$last" -le 2 ] && ok "title: last tick at ${last}s, never 0s" \
  || { ko "title: last tick at ${last:-nothing}s"; printf '       meta: %s\n' "$meta"; }
printf '%s\n' "$meta" | grep -- '--clear-title' \
  >/dev/null && ok "title: cleared on exit" || ko "title: cleared on exit"
[ -e "$CASE/tty" ] && ko "title: no automatic tty" || ok "title: no automatic tty"
printf '%s\n' "$meta" | grep -- '--ttl-ms' >/dev/null && ok "title: ttl on the lines" || ko "title: ttl on the lines"

# 13. --no-title: no metadata at all
case_new notitle
printf 'idle\nidle\nidle\nidle\n' > "$FAKE/status"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE" --no-title >/dev/null 2>&1
[ -s "$FAKE/meta" ] && ko "--no-title: no metadata" || ok "--no-title: no metadata"

# 14. the default threshold is 30s, not 60: measured on the first tick, not in the source
case_new default
printf 'idle\n' > "$FAKE/status"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" --poll 1 --pane "$PANE" >/dev/null 2>&1 &
defpid=$!
sleep 2
kill "$defpid" 2>/dev/null; wait "$defpid" 2>/dev/null
meta="$(cat "$FAKE/meta" 2>/dev/null)"
printf '%s\n' "$meta" | grep -- 'Pane closing in: 30s' >/dev/null && ok "default: 30s (from the title)" || { ko "default: 30s (from the title)"; printf '       got: %s\n' "$meta"; }
grep -q 'process-info' "$TARGET" && ko "no auto-detected tty" || ok "no auto-detected tty"

# 14b. --help: the whole leading comment block, not a line range that drifts
help="$("$TARGET" --help 2>&1)"
printf '%s' "$help" | grep 'Env: PANE_CLOSE_HERDR' >/dev/null && ok "--help: reaches the last comment line" || ko "--help: reaches the last comment line"
printf '%s' "$help" | grep 'set -uo pipefail' >/dev/null && ko "--help: prints no code" || ok "--help: prints no code"

# 15. a single pane: no registry to read, no second close
case_new single
printf 'idle\nidle\nidle\n' > "$FAKE/status"
printf '%s\n' "w5:pL${n}" > "${TMPDIR:-/tmp}/ingest-log-$(printf '%s' "$PANE" | tr -c 'A-Za-z0-9._-' '_').pane"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE" >/dev/null 2>&1
closed="$(tr '\n' ' ' < "$FAKE/closed")"
[ "$closed" = "$PANE " ] && ok "single pane: closes only its own" || { ko "single pane: closes only its own"; printf '       got: %s\n' "$closed"; }
rm -f "${TMPDIR:-/tmp}/ingest-log-$(printf '%s' "$PANE" | tr -c 'A-Za-z0-9._-' '_').pane"

# 16. JSON with spaces after the colons: it used to look like a vanished pane
case_new jsonspaces
printf 'idle\nidle\nidle\n' > "$FAKE/status"
FAKE_SPACES=1 PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE" >/dev/null 2>&1
[ "$(cat "$FAKE/closed")" = "$PANE" ] && ok "json with spaces: closes" || ko "json with spaces: closes"

# 17. herdr silent for one round: it must not throw the countdown away
case_new transient
printf 'ERR\nidle\nidle\nidle\n' > "$FAKE/status"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE" >/dev/null 2>&1
[ "$(cat "$FAKE/closed")" = "$PANE" ] && ok "transient herdr: retries and closes" || ko "transient herdr: retries and closes"

# 18. herdr silent forever: exits after 3 rounds without closing (never hangs)
case_new mute
printf 'ERR\n' > "$FAKE/status"
if run_and_kill 8 env PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE"; then
  ko "mute herdr: exits after 3 rounds"
else
  [ -s "$FAKE/closed" ] && ko "mute herdr: does not close" || ok "mute herdr: exits without closing"
fi

# 19. lock with a live but foreign pid: it must not block the close
case_new stalelock
printf 'idle\nidle\nidle\n' > "$FAKE/status"
sleep 60 2>/dev/null &
foreign=$!
printf '%s\n' "$foreign" > "${TMPDIR:-/tmp}/pane-close-later-$(printf '%s' "$PANE" | tr -c 'A-Za-z0-9._-' '_').pid"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE" >/dev/null 2>&1
[ "$(cat "$FAKE/closed")" = "$PANE" ] && ok "stale lock: carries on and closes" || ko "stale lock: carries on and closes"
kill "$foreign" 2>/dev/null; wait "$foreign" 2>/dev/null

# 19b. lock with a live pid that IS running this script: the close must wait, not start over.
#      (Without this, case 19 above would pass even if the script read a different lock path.)
case_new reallock
printf 'idle\nidle\nidle\n' > "$FAKE/status"
bash -c 'exec -a pane-close-later sleep 30' 2>/dev/null &
holder=$!
printf '%s\n' "$holder" > "${TMPDIR:-/tmp}/pane-close-later-$(printf '%s' "$PANE" | tr -c 'A-Za-z0-9._-' '_').pid"
PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE" >/dev/null 2>&1
[ -s "$FAKE/closed" ] && ko "live lock: a second countdown does not start" || ok "live lock: a second countdown does not start"
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null
rm -f "${TMPDIR:-/tmp}/pane-close-later-$(printf '%s' "$PANE" | tr -c 'A-Za-z0-9._-' '_').pid"

# 20. slow herdr: quiet is real time, not a number of ticks
case_new slow
printf 'idle\nidle\nidle\nidle\nidle\nidle\n' > "$FAKE/status"
started=$SECONDS
FAKE_SLOW=0.7 PANE_CLOSE_HERDR="$FAKE/herdr" "$TARGET" 2 --poll 1 --pane "$PANE" >/dev/null 2>&1
elapsed=$((SECONDS - started))
# What this can check: a slow herdr still closes and does not hang. What it cannot check
# reliably: that quiet follows the clock rather than the tick count — at these time scales
# the difference is within the noise of a loaded machine, so the bound is loose on purpose.
[ "$(cat "$FAKE/closed")" = "$PANE" ] && ok "slow herdr: still closes" || ko "slow herdr: still closes"
[ "$elapsed" -le 8 ] && ok "slow herdr: does not hang (${elapsed}s)" || ko "slow herdr: does not hang (${elapsed}s)"

echo ""
printf '%d ok, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
