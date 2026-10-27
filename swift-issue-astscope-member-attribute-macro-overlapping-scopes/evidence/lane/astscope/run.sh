#!/usr/bin/env bash
# Usage: SWIFTC=<compiler driver> astscope/run.sh <label>
# Builds the one-file plugin for 1, 2 and 14 generated attributes and
# compiles the same file against each: on a nested enum (default) and on an
# enum case (-D CASES). Then probes the toolchain's own @Observable.
label=$1
swiftc=${SWIFTC:-swiftc}
exe=""
[ "${OS:-}" = "Windows_NT" ] && exe=".exe"
$swiftc --version 2>&1 | head -3
report() {
  code=$1; name=$2
  sig=$(grep -m1 -E 'overlaps previous child|should not have attributes|Abort:|Assertion failed|error:' run.log)
  echo "RESULT $label $name exit=$code $sig"
  if [ $code -ne 0 ]; then sed -n '1,45p' run.log | sed 's/^/  | /'; fi
}
for n in N1 N2 N14; do
  plugin="p-$n$exe"
  if ! $swiftc -D PLUGIN -D $n astscope/repro.swift -o "$plugin" > build.log 2>&1; then
    echo "RESULT $label $n plugin-build-failed"
    cat build.log
    continue
  fi
  for shape in "" "-D CASES"; do
    for mode in "-typecheck" "-c -o out-$n.o"; do
      $swiftc $mode $shape -load-plugin-executable "$plugin#P" astscope/repro.swift > run.log 2>&1
      report $? "$n [$shape $mode]"
    done
  done
done
$swiftc -typecheck astscope/observable.swift > run.log 2>&1
report $? "observable [-typecheck]"
