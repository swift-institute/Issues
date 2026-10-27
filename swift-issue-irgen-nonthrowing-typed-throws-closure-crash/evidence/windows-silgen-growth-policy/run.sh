#!/bin/bash
# usage: run.sh <opts...>
swiftc --version 2>&1 | tee ver.txt
swiftc -frontend -version 2>&1 | head -3 || true
swiftc -frontend -help-hidden 2>/dev/null | grep -c "enable-llvm-verify\|sil-verify" || true
for f in v/*.swift v2/*.swift v3/*.swift; do
  swiftc -parse-as-library -module-name M -package-name p -swift-version 6 -Onone -enable-experimental-feature Lifetimes -c "$f" -o /tmp/out.o > /tmp/log.txt 2>&1
  code=$?
  grep -E "Assertion failed|Abort:|Initial term|While silgen|hasErrorResult" /tmp/log.txt | head -4 | sed 's/^/  LOG /'
  echo "RESULT $f exit=$code $(grep -m1 -E 'error:|Assertion' /tmp/log.txt)"
done
