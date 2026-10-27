#!/usr/bin/env bash
# swiftc of the swiftly toolchain named by $TOOLCHAIN.
exec "$HOME/.swiftly/bin/swiftly" run swiftc "$@" "+$TOOLCHAIN"
