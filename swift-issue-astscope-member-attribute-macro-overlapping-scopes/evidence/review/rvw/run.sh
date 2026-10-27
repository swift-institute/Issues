#!/bin/bash
# usage: run.sh <swiftc command words...>
SWIFTC=("$@")
"${SWIFTC[@]}" --version
W=$(mktemp -d)
for f in rvw/v*.swift; do
  n=$(basename "$f" .swift)
  mkdir -p "$W/$n"; cp "$f" "$W/$n/repro.swift"
  ( cd "$W/$n"
    "${SWIFTC[@]}" -D PLUGIN repro.swift -o plugin > build.txt 2>&1 || { echo "RESULT $n: PLUGIN BUILD FAILED"; head -20 build.txt; exit 0; }
    code=0; "${SWIFTC[@]}" -typecheck -load-plugin-executable 'plugin#P' repro.swift > out.txt 2>&1 || code=$?
    if grep -q "child overlaps previous child" out.txt; then r=OVERLAP; else r=NO-OVERLAP; fi
    echo "RESULT $n: exit=$code $r"
    head -14 out.txt | sed 's/^/    /'
    if [ "$n" = v00_baseline ]; then
      code=0; "${SWIFTC[@]}" -load-plugin-executable 'plugin#P' repro.swift -o client > out2.txt 2>&1 || code=$?
      grep -q "child overlaps previous child" out2.txt && r=OVERLAP || r=NO-OVERLAP
      echo "RESULT v00_baseline_without_typecheck_flag: exit=$code $r"
    fi
  )
done
