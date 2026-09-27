#!/bin/sh
# Lean 4 acceptance, for awb check: awb check ID -- model/accept.sh DIR [ACCEPT.lean]
# lake build in DIR (kernel-checked), no sorry/admit in its sources, and the theorems of
# ACCEPT.lean (the main agent's statements) typecheck against the build using only the standard
# axioms: #print axioms follows every dependency, so sorryAx, custom axioms and native_decide in
# the agent's code are caught.
# ponytail: theorems are found by regex, not by enumerating the environment (import Lean costs
# ~4s per check); anything unrecognised fails closed.
set -eu
[ $# -ge 1 ] || { echo "usage: $0 DIR [ACCEPT.lean]" >&2; exit 2; }
acc=${2:-}; [ -z "$acc" ] || acc=$(cd "$(dirname "$acc")" && pwd)/$(basename "$acc")
PATH=$HOME/.elan/bin:$PATH
cd "$1"
lake build
! grep -rnwE 'sorry|admit' --include='*.lean' --exclude-dir=.lake . || { echo "sorry/admit in sources"; exit 1; }
[ -n "$acc" ] || exit 0
t='^[[:space:]]*(@\[[^]]*\][[:space:]]*)*((private|protected|nonrec)[[:space:]]+)*theorem[[:space:]]+'
! grep -qwE 'example|namespace|section|lemma' "$acc" || { echo "ACCEPT: use top-level named theorems only"; exit 1; }
names=$(grep -E "$t" "$acc" | sed -E "s/$t([^[:space:](:{]+).*/\4/")
[ -n "$names" ] || { echo "ACCEPT has no theorem"; exit 1; }
[ "$(grep -cwE theorem "$acc")" = "$(printf '%s\n' "$names" | wc -l | tr -d ' ')" ] \
  || { echo "ACCEPT: unrecognised theorem syntax"; exit 1; }
trap 'rm -f .awb-accept.lean' EXIT
{ cat "$acc"; echo; printf '#print axioms %s\n' $names; } > .awb-accept.lean
out=$(lake env lean .awb-accept.lean 2>&1) || { printf '%s\n' "$out"; echo "acceptance statements do not typecheck"; exit 1; }
printf '%s\n' "$out"
! printf '%s\n' "$out" | grep -q "declaration uses 'sorry'" || { echo "sorry in ACCEPT"; exit 1; }
bad=$(printf '%s\n' "$out" | sed -n 's/.*depends on axioms: \[\(.*\)\].*/\1/p' | tr ',' '\n' \
      | tr -d ' ' | grep -vxE 'propext|Classical\.choice|Quot\.sound' | sort -u | tr '\n' ' ')
[ -z "$bad" ] || { echo "non-standard axioms: $bad"; exit 1; }
echo "axioms ok"
