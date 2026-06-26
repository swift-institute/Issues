#!/bin/sh
# Reproducer driver. Compiles defining module M (emit-module) then consumer module N (-c).
# PASS on NoAsserts (macOS/Linux); aborts at Mangler.cpp:176 on a +Asserts toolchain (Windows
# 6.3.x, or the swiftlang/swift:nightly-6.3-jammy Linux image).
#
#   Local (host) :  sh build.sh .
#   +Asserts     :  docker run --rm -v "$PWD":/w -w /w swiftlang/swift:nightly-6.3-jammy sh build.sh .
WD="${1:-.}"
F="-swift-version 6 -enable-experimental-feature SuppressedAssociatedTypes -enable-experimental-feature Lifetimes"
rm -f "$WD/M.swiftmodule" "$WD/M.swiftdoc" "$WD/M.abi.json" "$WD/n.o"
swift --version 2>&1 | head -2
# shellcheck disable=SC2086
swiftc $F -wmo -parse-as-library -emit-module -emit-module-path "$WD/M.swiftmodule" -module-name M "$WD/defining.swift" || { echo "[[M-FAILED]]"; exit 2; }
# shellcheck disable=SC2086
swiftc $F -wmo -parse-as-library -c "$WD/consumer.swift" -I "$WD" -module-name N -o "$WD/n.o" || { echo "[[N-FAILED]]"; exit 3; }
echo "[[ALL-OK]]"
