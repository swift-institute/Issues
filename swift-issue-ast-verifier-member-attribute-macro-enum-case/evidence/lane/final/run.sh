#!/usr/bin/env bash
# Usage: SWIFTC=<compiler driver> final/run.sh <label>
# The two records' reproductions exactly as drafted, run in a fresh directory.
label=$1
swiftc=${SWIFTC:-swiftc}
exe=""
[ "${OS:-}" = "Windows_NT" ] && exe=".exe"
$swiftc --version 2>&1 | head -3
for f in scope case; do
  dir=$(mktemp -d)
  cp "final/$f.swift" "$dir/repro.swift"
  ( cd "$dir"
    $swiftc -D PLUGIN repro.swift -o "plugin$exe" > build.log 2>&1 || { echo "RESULT $label $f plugin-build-failed"; cat build.log; exit 0; }
    $swiftc -typecheck -load-plugin-executable "plugin$exe#P" repro.swift > run.log 2>&1
    code=$?
    sig=$(grep -m1 -E 'overlaps previous child|should not have attributes|Abort:|Assertion failed|error:' run.log)
    echo "RESULT $label $f exit=$code $sig"
    sed -n '1,60p' run.log | sed 's/^/  | /' )
done
