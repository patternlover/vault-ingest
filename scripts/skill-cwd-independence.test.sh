#!/usr/bin/env bash
# Test dell'indipendenza dalla cwd: la skill viene lanciata da pane che possono stare in un
# altro repo (herdr: un workspace per repo/task). Se uno step usa `git` o `<validator>` senza
# nominare il vault, l'ingest fa pull/commit/push sul repo sbagliato — un guasto silenzioso,
# perche' i comandi riescono e il vault resta indietro.
# Uso: ./skill-cwd-independence.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$HERE/../SKILL.md"
pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

echo "skill-cwd-independence: test"

[ -f "$SKILL" ] && ok "SKILL.md c'e'" || { ko "SKILL.md c'e'"; printf '%d ok, %d fail\n' "$pass" "$fail"; exit 1; }

# Solo gli Steps: la sezione Config parla del repo della skill, dove `git pull` e' legittimo.
body="$(awk '/^## Steps$/{f=1} f' "$SKILL")"

# 1. la regola esiste, in cima agli Steps: senza quella, gli step successivi sembrano opzionali
printf '%s\n' "$body" | grep -q 'Every command below names the vault' \
  && ok "regola 'ogni comando nomina il vault' presente" \
  || ko "regola 'ogni comando nomina il vault' presente"

# 2. nessun comando git che operi sul vault senza -C <vault_root>.
#    Eccezione dichiarata: il divieto "never `git add -A`" e' prosa, non un comando da eseguire.
bare="$(printf '%s\n' "$body" | grep -nE 'git (-c|add|commit|push|pull|status)' \
  | grep -vF -- '<vault_root>' \
  | grep -vF -- 'never `git add -A`' || true)"
if [ -z "$bare" ]; then
  ok "nessun comando git senza -C <vault_root>"
else
  ko "comando git senza -C <vault_root>:"
  printf '%s\n' "$bare" | sed 's/^/       /'
fi

# 3. la vecchia forma relativa non deve tornare (era il guasto: pull sul repo della pane)
printf '%s\n' "$body" | grep -qF -- 'git -c rebase.autoStash=true pull --rebase`' \
  && ko "pull relativo senza -C <vault_root>" \
  || ok "nessun pull relativo"

# 4. il validator gira nel vault, non nella cwd della sessione
printf '%s\n' "$body" | grep -qF "cd <vault_root> && <validator>" \
  && ok "validator con cwd = <vault_root>" \
  || ko "validator con cwd = <vault_root>"

# 5. niente titolo duplicato: due '## Steps' di fila erano un residuo di merge
[ "$(printf '%s\n' "$body" | grep -c '^## Steps$')" -eq 1 ] \
  && ok "un solo '## Steps'" \
  || ko "un solo '## Steps'"

echo ""
printf '%d ok, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
