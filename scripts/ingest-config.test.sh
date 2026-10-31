#!/usr/bin/env bash
# Test di ingest-config: file macchina e file vault finti in una temp dir, nessun path vero.
# Uso: ./ingest-config.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HERE/ingest-config"
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/icfg-test.XXXXXX")"
export TMPDIR="$TMPROOT/tmp"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPROOT"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

HOMEFIX="$TMPROOT/home"
mkdir -p "$HOMEFIX"
# Isola la macchina: senza questo il test legge la config vera dell'utente
# (~/.config/vault-ingest/config.toml) e il caso "nessuna config" passa per sbaglio.
run() {
  HOME="$HOMEFIX" XDG_CONFIG_HOME="$HOMEFIX/.config" APPDATA="$HOMEFIX/appdata" \
    INGEST_CONFIG="$CFG" bash "$TARGET" "$@"
}

echo "ingest-config: test"

VAULT="$TMPROOT/vault"
mkdir -p "$VAULT"
printf '# vault\n' > "$VAULT/AGENTS.md"

# 1. nessun file: vault_root vuoto, e la chiave singola esce 1
CFG="$TMPROOT/none.toml"
run vault_root >/dev/null 2>&1
[ $? -eq 1 ] && ok "no config: vault_root exits 1" || ko "no config: vault_root exits 1"
run --check >/dev/null 2>&1
[ $? -eq 1 ] && ok "no config: --check exits 1" || ko "no config: --check exits 1"

# 2. defaults quando il file c'e' ma la chiave no
CFG="$TMPROOT/empty.toml"
: > "$CFG"
[ "$(run vault_marker)" = "AGENTS.md" ] && ok "default: vault_marker" || ko "default: vault_marker"
[ "$(run validator)" = "none" ] && ok "default: validator" || ko "default: validator"
[ "$(run commit_prefix)" = "[pi]" ] && ok "default: commit_prefix" || ko "default: commit_prefix"
[ "$(run log_dir)" = "log" ] && ok "default: log_dir" || ko "default: log_dir"

# 3. file macchina: virgolette, commento in linea, spazi
CFG="$TMPROOT/machine.toml"
cat > "$CFG" <<EOF
[ingest]
vault_root   =   "$VAULT"
validator = "true"   # commento in linea

commit_prefix = "[bot]"
EOF
[ "$(run vault_root)" = "$VAULT" ] && ok "machine file: reads vault_root" || { ko "machine file: reads vault_root"; run vault_root; }
[ "$(run validator)" = "true" ] && ok "machine file: strips quotes and trailing comment" || { ko "machine file: strips quotes and trailing comment"; run validator; }
[ "$(run commit_prefix)" = "[bot]" ] && ok "machine file: reads commit_prefix" || ko "machine file: reads commit_prefix"

# 4. file del vault: vince sul file macchina, e accetta anche `chiave: valore`
cat > "$VAULT/.ingest.toml" <<'EOF'
# Config di questo vault
log_dir: log
log_lang: english
validator: none
EOF
[ "$(run log_dir)" = "log" ] && ok "vault file: wins over the machine file" || { ko "vault file: wins over the machine file"; run log_dir; }
[ "$(run log_lang)" = "english" ] && ok "vault file: colon syntax" || ko "vault file: colon syntax"
[ "$(run validator)" = "none" ] && ok "vault file: overrides a default" || ko "vault file: overrides a default"

# 5. --file elenca macchina e vault; --check passa
run --file | grep -x "$CFG" >/dev/null && ok "--file: machine file" || ko "--file: machine file"
run --file | grep -x "$VAULT/.ingest.toml" >/dev/null && ok "--file: vault file" || ko "--file: vault file"
run --check >/dev/null 2>&1 && ok "--check: green" || ko "--check: green"

# 5b. fallback: un vault con .ingest.md (vecchio schema) si legge lo stesso
mv "$VAULT/.ingest.toml" "$VAULT/.ingest.md"
[ "$(run log_dir)" = "log" ] && ok "fallback: .ingest.md" || ko "fallback: .ingest.md"
mv "$VAULT/.ingest.md" "$VAULT/.ingest.toml"

# 6. tutte le chiavi in un colpo, senza valori vuoti
all="$(run)"
for k in vault_root vault_marker log_dir validator commit_prefix log_lang; do
  printf '%s\n' "$all" | grep "^$k=" >/dev/null || { ko "all keys: $k"; all=""; }
done
[ -n "$all" ] && ok "all keys: present" || ko "all keys: present"
printf '%s\n' "$all" | grep '^log_file=$' >/dev/null && ok "key without default: empty, not missing" || ko "key without default: empty, not missing"

# 7. vault inesistente: --check esce 1
CFG="$TMPROOT/broken.toml"
printf 'vault_root = "%s/non-esiste"\n' "$TMPROOT" > "$CFG"
run --check >/dev/null 2>&1
[ $? -eq 1 ] && ok "--check: missing vault exits 1" || ko "--check: missing vault exits 1"

# 8. chiave sconosciuta: exit 1, e opzione sconosciuta: exit 2
CFG="$TMPROOT/machine.toml"
run boh >/dev/null 2>&1
[ $? -eq 1 ] && ok "unknown key: exit 1" || ko "unknown key: exit 1"
run --boh >/dev/null 2>&1
[ $? -eq 2 ] && ok "unknown option: exit 2" || ko "unknown option: exit 2"

echo ""
printf '%d ok, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
