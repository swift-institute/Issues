#!/bin/bash
# usage: run.sh <swiftc command...>
SWIFTC=("$@")
cd "$(dirname "$0")"
"${SWIFTC[@]}" --version
t() { perl -e 'alarm 300; exec @ARGV' "$@"; }
check() {
  local name=$1; shift
  local out; out=$(t "$@" 2>&1); local rc=$?
  if grep -q "EnumCaseDecl should not have attributes" <<<"$out"; then r=FAILS_SAME; elif [ $rc -eq 0 ]; then r=ACCEPTED; else r="OTHER_rc$rc"; fi
  echo "RESULT $name: $r"
  echo "$out" | head -25 | sed 's/^/    /'
}
for f in v*.swift; do
  n=${f%.swift}; d=$(mktemp -d); cp "$f" "$d/repro.swift"
  ( cd "$d" && "${SWIFTC[@]}" -D PLUGIN repro.swift -o plugin >build.log 2>&1 ) || { echo "RESULT $n: PLUGIN_BUILD_FAILED"; head -20 "$d/build.log"; continue; }
  ( cd "$d" && check "$n" "${SWIFTC[@]}" -typecheck -load-plugin-executable 'plugin#P' repro.swift )
  if [ "$n" = v0 ]; then
    ( cd "$d" && check v0_no_typecheck_flag "${SWIFTC[@]}" -load-plugin-executable 'plugin#P' repro.swift )
    ( cd "$d" && check v0_parse_only "${SWIFTC[@]}" -parse -load-plugin-executable 'plugin#P' repro.swift )
  fi
done
