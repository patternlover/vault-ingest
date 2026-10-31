#!/usr/bin/env bash
# Test del frontmatter di SKILL.md: se non parsa, pi scarta la skill in silenzio e
# `/skill:ingest` semplicemente non esiste (successo il 2026-10-31: una description con
# dentro ": " rompe lo YAML). Qui si controlla la forma senza dipendenze esterne.
# Uso: ./skill-frontmatter.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$HERE/../SKILL.md"
pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

echo "skill-frontmatter: test"

[ -f "$SKILL" ] && ok "SKILL.md c'e'" || { ko "SKILL.md c'e'"; printf '%d ok, %d fail\n' "$pass" "$fail"; exit 1; }

# 1. frontmatter delimitato, con name e description
head -1 "$SKILL" | grep -qx -- '---' && ok "apre con ---" || ko "apre con ---"
awk 'NR>1 && /^---$/ { found=1; exit } END { exit found ? 0 : 1 }' "$SKILL" \
  && ok "chiude il frontmatter" || ko "chiude il frontmatter"
dirdir="$(basename "$(cd "$HERE/.." && pwd)")"
name="$(sed -n 's/^name: *//p' "$SKILL" | head -1 | tr -d '"')"
[ -n "$name" ] && ok "name c'e' ($name)" || ko "name c'e'"
[ "$name" = "ingest" ] && ok "name: ingest" || ko "name: ingest (trovato '$name')"
# il comando nasce dal nome della cartella di installazione, non dal nome del repo:
# qui il repo si chiama vault-ingest e la skill si invoca /skill:ingest

desc="$(sed -n 's/^description: *//p' "$SKILL" | head -1)"
[ -n "$desc" ] && ok "description c'e'" || ko "description c'e'"

# 2. la trappola vera: uno scalare NON quotato non puo' contenere ": "
case "$desc" in
  \"*|\'*|'>'*|'|'*)
    ok "description quotata o block scalar" ;;
  *)
    case "$desc" in
      *": "*) ko "description non quotata con ': ' dentro (rompe lo YAML)" ;;
      *) ok "description semplice, senza ': '" ;;
    esac
    ;;
esac

# 3. niente tab, niente BOM, niente CR: YAML vuole spazi, e il repo e' LF/UTF-8
head -c3 "$SKILL" | od -An -tx1 | grep -q "ef bb bf" && ko "niente BOM" || ok "niente BOM"
grep -qP "\t" "$SKILL" 2>/dev/null && ko "niente tab nel frontmatter" || ok "niente tab nel frontmatter"
LC_ALL=C grep -q "$(printf '\r')" "$SKILL" && ko "niente CR (line ending LF)" || ok "niente CR (line ending LF)"

# 4. le chiavi che contano stanno nel frontmatter, non sparse nel corpo
awk 'NR==1{next} /^---$/{exit} /^(name|description|license|allowed-tools|disable-model-invocation):/{print}' "$SKILL" \
  | wc -l | tr -d ' ' | grep -qx '2' && ok "solo name+description nel frontmatter" \
  || { ko "solo name+description nel frontmatter"; awk 'NR==1{next} /^---$/{exit} {print}' "$SKILL" | cut -c1-40; }

echo ""
printf '%d ok, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
