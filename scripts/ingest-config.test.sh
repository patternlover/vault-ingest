#!/usr/bin/env bash
# Test di ingest-config: file macchina e file vault finti in una temp dir, nessun path vero.
# Uso: ./ingest-config.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HERE/ingest-config"
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/icfg-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

run() { INGEST_CONFIG="$CFG" bash "$TARGET" "$@"; }

echo "ingest-config: test"

VAULT="$TMPROOT/vault"
mkdir -p "$VAULT"
printf '# vault\n' > "$VAULT/AGENTS.md"

# 1. nessun file: vault_root vuoto, e la chiave singola esce 1
CFG="$TMPROOT/none.toml"
run vault_root >/dev/null 2>&1
[ $? -eq 1 ] && ok "senza config: vault_root esce 1" || ko "senza config: vault_root esce 1"
run --check >/dev/null 2>&1
[ $? -eq 1 ] && ok "senza config: --check esce 1" || ko "senza config: --check esce 1"

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
validator = "node scripts/validate.mjs"   # commento in linea

commit_prefix = "[pi-home]"
EOF
[ "$(run vault_root)" = "$VAULT" ] && ok "macchina: legge vault_root" || { ko "macchina: legge vault_root"; run vault_root; }
[ "$(run validator)" = "node scripts/validate.mjs" ] && ok "macchina: toglie virgolette e commento" || { ko "macchina: toglie virgolette e commento"; run validator; }
[ "$(run commit_prefix)" = "[pi-home]" ] && ok "macchina: legge commit_prefix" || ko "macchina: legge commit_prefix"

# 4. file del vault: vince sul file macchina, e accetta anche `chiave: valore`
cat > "$VAULT/.ingest.md" <<'EOF'
# Config di questo vault
log_dir: 90 System/Log
log_lang: italiano
validator: none
EOF
[ "$(run log_dir)" = "90 System/Log" ] && ok "vault: vince su macchina" || { ko "vault: vince su macchina"; run log_dir; }
[ "$(run log_lang)" = "italiano" ] && ok "vault: sintassi con i due punti" || ko "vault: sintassi con i due punti"
[ "$(run validator)" = "none" ] && ok "vault: sovrascrive anche il default" || ko "vault: sovrascrive anche il default"

# 5. --file elenca macchina e vault; --check passa
run --file | grep -x "$CFG" >/dev/null && ok "--file: file macchina" || ko "--file: file macchina"
run --file | grep -x "$VAULT/.ingest.md" >/dev/null && ok "--file: file vault" || ko "--file: file vault"
run --check >/dev/null 2>&1 && ok "--check: verde" || ko "--check: verde"

# 6. tutte le chiavi in un colpo, senza valori vuoti
all="$(run)"
for k in vault_root vault_marker log_dir validator commit_prefix log_lang; do
  printf '%s\n' "$all" | grep "^$k=" >/dev/null || { ko "tutte le chiavi: $k"; all=""; }
done
[ -n "$all" ] && ok "tutte le chiavi: presenti" || ko "tutte le chiavi: presenti"
printf '%s\n' "$all" | grep '^log_file=$' >/dev/null && ok "chiave senza default: vuota, non assente" || ko "chiave senza default: vuota, non assente"

# 7. vault inesistente: --check esce 1
CFG="$TMPROOT/broken.toml"
printf 'vault_root = "%s/non-esiste"\n' "$TMPROOT" > "$CFG"
run --check >/dev/null 2>&1
[ $? -eq 1 ] && ok "--check: vault mancante esce 1" || ko "--check: vault mancante esce 1"

# 8. chiave sconosciuta: exit 1, e opzione sconosciuta: exit 2
CFG="$TMPROOT/machine.toml"
run boh >/dev/null 2>&1
[ $? -eq 1 ] && ok "chiave sconosciuta: exit 1" || ko "chiave sconosciuta: exit 1"
run --boh >/dev/null 2>&1
[ $? -eq 2 ] && ok "opzione sconosciuta: exit 2" || ko "opzione sconosciuta: exit 2"

echo ""
printf '%d ok, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
