#!/usr/bin/env bash
# Usage: SWIFTC=<compiler driver> astscope/min.sh <label>
# Reduction variants of astscope/min.swift: plugin emitting "@A" or "@A @A",
# against each test shape.
label=$1
swiftc=${SWIFTC:-swiftc}
exe=""
[ "${OS:-}" = "Windows_NT" ] && exe=".exe"
$swiftc --version 2>&1 | head -3
for n in ONE TWO; do
  plugin="m-$n$exe"
  if ! $swiftc -D PLUGIN -D $n astscope/min.swift -o "$plugin" > build.log 2>&1; then
    echo "RESULT $label $n plugin-build-failed"
    cat build.log
    continue
  fi
  for shape in DEFAULT R_STRUCT R_NOCONFORM R_NESTSTRUCT R_CASE; do
    $swiftc -typecheck -D $shape -load-plugin-executable "$plugin#P" astscope/min.swift > run.log 2>&1
    code=$?
    sig=$(grep -m1 -E 'overlaps previous child|should not have attributes|Abort:|Assertion failed|error:' run.log)
    echo "RESULT $label $n $shape exit=$code $sig"
    if [ $code -ne 0 ] && [ -z "$sig" ]; then sed -n '1,20p' run.log | sed 's/^/  | /'; fi
  done
done
for n in AVAIL ACTOR ACTORA; do
  plugin="m-$n$exe"
  $swiftc -D PLUGIN -D $n astscope/min.swift -o "$plugin" > build.log 2>&1 || { echo "RESULT $label $n plugin-build-failed"; continue; }
  for shape in "R_CASE" "R_CASE -D NOPEER" "R_STRUCT" "R_STRUCT -D NOPEER"; do
    $swiftc -typecheck -D $shape -load-plugin-executable "$plugin#P" astscope/min.swift > run.log 2>&1
    code=$?
    sig=$(grep -m1 -E 'overlaps previous child|should not have attributes|Abort:|Assertion failed|error:' run.log)
    echo "RESULT $label $n $shape exit=$code $sig"
  done
done
