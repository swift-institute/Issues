#!/bin/sh
# Reproducer driver for the typed-throws nested-generic-error IRGen ICE.
# PASS on NoAsserts (macOS/Linux); aborts at hasErrorResult() (AST/Types.h) on a +Asserts
# toolchain (Windows 6.3.x, or swiftlang/swift:nightly-6.3-jammy).
#
#   host (NoAsserts):  sh build.sh .
#   +Asserts:          docker run --rm -v "$PWD":/w -w /w swiftlang/swift:nightly-6.3-jammy sh build.sh .
WD="${1:-.}"
swift --version 2>&1 | head -2
swiftc -g -Onone -swift-version 6 "$WD/main.swift" -o "$WD/a.out" \
    || { echo "[[FAILED]]"; exit 2; }
echo "[[ALL-OK]]"
