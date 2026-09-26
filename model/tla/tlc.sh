#!/bin/sh
# Model-check every config with TLC: each *Fixed.cfg must pass; every other config reproduces
# a bug of an earlier version and must be violated. TLA2TOOLS: path of tla2tools.jar.
cd "$(dirname "$0")" || exit 1
jar=${TLA2TOOLS:-$HOME/.local/share/tla/tla2tools.jar}
[ -f "$jar" ] || { echo "tla2tools.jar not found; set TLA2TOOLS"; exit 2; }
rc=0
for c in *.cfg; do
  for f in *.tla; do case $c in "${f%.tla}"*) m=${f%.tla} ;; esac; done
  d=$(mktemp -d)
  out=$(java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers auto -metadir "$d" -config "$c" -deadlock "$m" 2>&1 \
        | grep -E 'No error has been found|is violated|was violated|exception|Error:' | head -1)
  rm -rf "$d"; rm -f ./*_TTrace_*
  case $c in *Fixed.cfg) want="No error" ;; *) want="violated" ;; esac
  case $out in *"$want"*) echo "ok   $c: $out" ;; *) echo "FAIL $c: $out"; rc=1 ;; esac
done
exit $rc
