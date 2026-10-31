#!/usr/bin/env bash
# Test for ensure-pane-title: runs on fake config.toml files in a temp dir, with a fake
# herdr for `server reload-config`. No real file, no real reload.
# Usage: ./ensure-pane-title.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HERE/ensure-pane-title"
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/ept-test.XXXXXX")"
pass=0
fail=0

ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

trap 'rm -rf "$TMPROOT"' EXIT

FAKE="$TMPROOT/bin"
mkdir -p "$FAKE"
cat > "$FAKE/herdr" <<'FAKEH'
#!/usr/bin/env bash
d="$(dirname "$0")"
echo "$*" >> "$d/calls"
case "$1 $2" in
  "server reload-config")
    if [ -s "$d/fail" ]; then
      printf '{"id":"cli:server:reload-config","error":{"code":"config"}}\n'
      exit 1
    fi
    printf '{"id":"cli:server:reload-config","result":{"diagnostics":[],"status":"applied","type":"config_reload"}}\n'
    ;;
  *) echo "fake herdr: unexpected command: $*" >&2; exit 2 ;;
esac
FAKEH
chmod +x "$FAKE/herdr"

run() { ENSURE_TITLE_CONFIG="$1" ENSURE_TITLE_HERDR="$FAKE/herdr" bash "$TARGET" 2>&1; }
kk() { grep -c "pane_borders = \"always\"" "$1" 2>/dev/null; }

echo "ensure-pane-title: test"

# 1. [ui] without the three keys: adds them right below [ui] and reloads
cfg1="$TMPROOT/c1.toml"
printf 'onboarding = false\n\n[ui]\nstatus_indicators = "dots"\n\n[theme]\nname = "gruvbox"\n' > "$cfg1"
before1="$(cksum < "$cfg1")"
: > "$FAKE/calls"
out1="$(run "$cfg1")"
[ $? -eq 0 ] && ok "missing keys: exit 0" || { ko "missing keys: exit 0"; printf '       %s\n' "$out1"; }
[ "$(kk "$cfg1")" = "1" ] && ok "missing keys: adds pane_borders" || ko "missing keys: adds pane_borders"
grep -q '^pane_outer_borders = true$' "$cfg1" && ok "missing keys: adds pane_outer_borders" || ko "missing keys: adds pane_outer_borders"
grep -q '^show_agent_labels_on_pane_borders = true$' "$cfg1" && ok "missing keys: adds the agent labels" || ko "missing keys: adds the agent labels"
# position: after [ui] and before [theme], otherwise herdr reads them in the wrong section
awk '/^\[ui\]/{u=NR} /^pane_borders/{b=NR} /^\[theme\]/{t=NR} END{exit (u && b && t && u<b && b<t) ? 0 : 1}' "$cfg1" \
  && ok "missing keys: inside [ui], not in [theme]" || ko "missing keys: inside [ui], not in [theme]"
[ -f "$cfg1.before-pane-title" ] && ok "missing keys: backup" || ko "missing keys: backup"
[ "$(cksum < "$cfg1.before-pane-title")" = "$before1" ] && ok "missing keys: backup = original" || ko "missing keys: backup = original"
grep -q 'status_indicators = "dots"' "$cfg1" && ok "missing keys: leaves the rest alone" || ko "missing keys: leaves the rest alone"
grep -q '^pane_outer_borders = true$' "$cfg1" && [ "$(grep -c '^\[theme\]$' "$cfg1")" = "1" ] && ok "missing keys: sections intact" || ko "missing keys: sections intact"
grep -q 'server reload-config' "$FAKE/calls" && ok "missing keys: reload" || ko "missing keys: reload"

# 2. wrong values: replaced, no duplicates
cfg2="$TMPROOT/c2.toml"
printf '[ui]\npane_borders = "auto"\npane_outer_borders = false\nshow_agent_labels_on_pane_borders = false\n' > "$cfg2"
out2="$(run "$cfg2")"
[ "$(kk "$cfg2")" = "1" ] && ok "wrong values: a single pane_borders" || { ko "wrong values: a single pane_borders"; cat "$cfg2"; }
[ "$(grep -c '^pane_outer_borders' "$cfg2")" = "1" ] && ok "wrong values: a single pane_outer_borders" || ko "wrong values: a single pane_outer_borders"
grep -q 'false' "$cfg2" && ko "wrong values: no leftover false" || ok "wrong values: no leftover false"

# 3. already on: identical file, no backup, no reload
cfg3="$TMPROOT/c3.toml"
printf '[ui]\npane_borders = "always"\npane_outer_borders = true\nshow_agent_labels_on_pane_borders = true\n' > "$cfg3"
sum3="$(cksum < "$cfg3")"
: > "$FAKE/calls"
out3="$(run "$cfg3")"
[ $? -eq 0 ] && ok "already on: exit 0" || ko "already on: exit 0"
[ "$(cksum < "$cfg3")" = "$sum3" ] && ok "already on: file untouched" || ko "already on: file untouched"
[ -f "$cfg3.before-pane-title" ] && ko "already on: no backup" || ok "already on: no backup"
[ -s "$FAKE/calls" ] && ko "already on: no reload" || ok "already on: no reload"
printf '%s' "$out3" | grep -i 'ok' >/dev/null && ok "already on: it says so" || ko "already on: it says so"

# 4. no [ui] section: creates it
cfg4="$TMPROOT/c4.toml"
printf '[theme]\nname = "gruvbox"\n' > "$cfg4"
run "$cfg4" >/dev/null 2>&1
awk '/^\[ui\]/{u=NR} /^pane_borders/{b=NR} END{exit (u && b && u<b) ? 0 : 1}' "$cfg4" \
  && ok "without [ui]: creates the section" || { ko "without [ui]: creates the section"; cat "$cfg4"; }
[ "$(grep -c '^\[ui\]$' "$cfg4")" = "1" ] && ok "without [ui]: a single section" || ko "without [ui]: a single section"

# 5. same-named keys under [ui.sound]: they do not count as [ui]
cfg5="$TMPROOT/c5.toml"
printf '[ui]\nstatus_indicators = "dots"\n\n[ui.sound]\npane_borders = "off"\n' > "$cfg5"
run "$cfg5" >/dev/null 2>&1
[ "$(kk "$cfg5")" = "1" ] && ok "subsection: adds the keys in [ui]" || ko "subsection: adds the keys in [ui]"
awk '/^\[ui\]/{u=NR} /^pane_borders = "always"/{b=NR} /^\[ui.sound\]/{s=NR} END{exit (u && b && s && u<b && b<s) ? 0 : 1}' "$cfg5" \
  && ok "subsection: keys before [ui.sound]" || ko "subsection: keys before [ui.sound]"
grep -q '^pane_borders = "off"$' "$cfg5" && ok "subsection: leaves [ui.sound] alone" || ko "subsection: leaves [ui.sound] alone"

# 6. two passes: the second changes nothing
run "$cfg5" >/dev/null 2>&1
sum5="$(cksum < "$cfg5")"
run "$cfg5" >/dev/null 2>&1
[ "$(cksum < "$cfg5")" = "$sum5" ] && ok "idempotent: second pass changes nothing" || ko "idempotent: second pass changes nothing"

# 7. no path given and nothing found: exit 0, creates nothing, says what it tried
#    (better no title than a config written in the wrong place)
home7="$TMPROOT/home7"; mkdir -p "$home7"
out7="$(env -u ENSURE_TITLE_CONFIG -u HERDR_CONFIG_PATH HOME="$home7" XDG_CONFIG_HOME="$home7/xdg" \
  ENSURE_TITLE_HERDR="$FAKE/herdr" bash "$TARGET" 2>&1)"; rc7=$?
[ "$rc7" -eq 0 ] && ok "path not found: exit 0" || ko "path not found: exit 0"
[ -e "$home7/xdg/herdr/config.toml" ] && ko "path not found: does not create the file" || ok "path not found: does not create the file"
printf '%s' "$out7" | grep 'xdg/herdr/config.toml' >/dev/null && ok "path not found: lists the paths it tried" || ko "path not found: lists the paths it tried"
printf '%s' "$out7" | grep "pass the path" >/dev/null && ok "path not found: says how to pass the path" || ko "path not found: says how to pass the path"

# 7b. explicit path that does not exist: the agent decided where, so it creates it
cfg7b="$TMPROOT/new/c7b.toml"
out7b="$(run "$cfg7b")"; rc7b=$?
[ "$rc7b" -eq 0 ] && ok "explicit missing path: exit 0" || { ko "explicit missing path: exit 0"; printf '       %s\n' "$out7b"; }
[ "$(kk "$cfg7b")" = "1" ] && ok "explicit missing path: creates it with [ui]" || ko "explicit missing path: creates it with [ui]"
grep -q '^pane_outer_borders = true$' "$cfg7b" 2>/dev/null && ok "explicit missing path: all three keys" || ko "explicit missing path: all three keys"
[ -f "$cfg7b.before-pane-title" ] && ko "explicit missing path: no backup of the void" || ok "explicit missing path: no backup of the void"

# 7c. path precedence, as in herdr: HERDR_CONFIG_PATH > XDG_CONFIG_HOME > APPDATA
h17="$TMPROOT/h7c"; mkdir -p "$h17/.config/herdr" "$h17/xdg/herdr" "$h17/appdata/herdr"
for f in "$h17/.config/herdr/config.toml" "$h17/xdg/herdr/config.toml" "$h17/appdata/herdr/config.toml"; do
  printf '[ui]\nstatus_indicators = "dots"\n' > "$f"
done
env -u ENSURE_TITLE_CONFIG HOME="$h17" XDG_CONFIG_HOME="$h17/xdg" APPDATA="$h17/appdata" \
  HERDR_CONFIG_PATH="$h17/.config/herdr/config.toml" ENSURE_TITLE_HERDR="$FAKE/herdr" bash "$TARGET" >/dev/null 2>&1
[ "$(kk "$h17/.config/herdr/config.toml")" = "1" ] && ok "HERDR_CONFIG_PATH wins over everything" || ko "HERDR_CONFIG_PATH wins over everything"
[ "$(kk "$h17/xdg/herdr/config.toml")" = "0" ] && ok "HERDR_CONFIG_PATH: XDG untouched" || ko "HERDR_CONFIG_PATH: XDG untouched"
env -u ENSURE_TITLE_CONFIG -u HERDR_CONFIG_PATH HOME="$h17" XDG_CONFIG_HOME="$h17/xdg" APPDATA="$h17/appdata" \
  ENSURE_TITLE_HERDR="$FAKE/herdr" bash "$TARGET" >/dev/null 2>&1
[ "$(kk "$h17/xdg/herdr/config.toml")" = "1" ] && ok "XDG_CONFIG_HOME wins over APPDATA" || ko "XDG_CONFIG_HOME wins over APPDATA"
[ "$(kk "$h17/appdata/herdr/config.toml")" = "0" ] && ok "XDG_CONFIG_HOME: APPDATA untouched" || ko "XDG_CONFIG_HOME: APPDATA untouched"
env -u ENSURE_TITLE_CONFIG -u HERDR_CONFIG_PATH -u XDG_CONFIG_HOME HOME="$h17" APPDATA="$h17/appdata" \
  ENSURE_TITLE_HERDR="$FAKE/herdr" bash "$TARGET" >/dev/null 2>&1
[ "$(kk "$h17/appdata/herdr/config.toml")" = "1" ] && ok "Windows: uses %APPDATA%/herdr, like herdr" || ko "Windows: uses %APPDATA%/herdr, like herdr"

# 8. red reload: restores the file and exits 1
cfg8="$TMPROOT/c8.toml"
printf '[ui]\nstatus_indicators = "dots"\n' > "$cfg8"
sum8="$(cksum < "$cfg8")"
echo 1 > "$FAKE/fail"
out8="$(run "$cfg8")"; rc8=$?
[ "$rc8" -eq 1 ] && ok "red reload: exit 1" || ko "red reload: exit 1"
[ "$(cksum < "$cfg8")" = "$sum8" ] && ok "red reload: file restored" || { ko "red reload: file restored"; cat "$cfg8"; }
rm -f "$FAKE/fail"

# 9. herdr missing: writes the config but says so, exit 1 (ingest carries on anyway)
cfg9="$TMPROOT/c9.toml"
printf '[ui]\nstatus_indicators = "dots"\n' > "$cfg9"
out9="$(ENSURE_TITLE_CONFIG="$cfg9" ENSURE_TITLE_HERDR="$TMPROOT/bin/nope" bash "$TARGET" 2>&1)"; rc9=$?
[ "$rc9" -eq 1 ] && ok "herdr missing: exit 1" || ko "herdr missing: exit 1"
printf '%s' "$out9" | grep -i 'herdr' >/dev/null && ok "herdr missing: it says so" || ko "herdr missing: it says so"

echo ""
printf '%d ok, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
