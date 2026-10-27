#!/bin/bash
# Stand-in for an assertions swiftc. It replays the abort text recorded on CI
# (STUB_REPLAY=<file>) instead of compiling; with STUB_REPLAY unset it exits 0,
# like an assertions build without the bug. It does not reproduce anything.
if [ "$1" = "--version" ]; then
  echo "Swift version 6.5-dev (LLVM 9b3700c0bd7ce7a, Swift f62414fd1d17227)"
  echo "Target: x86_64-unknown-linux-gnu"
  echo "Build config: +assertions"; exit 0
fi
for a in "$@"; do [ "$a" = "PLUGIN" ] && exit 0; done
if [ -n "$STUB_REPLAY" ]; then cat "$STUB_REPLAY" >&2; exit 134; fi
exit 0
