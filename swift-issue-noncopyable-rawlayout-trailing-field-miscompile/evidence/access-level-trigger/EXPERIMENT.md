# @_rawLayout LLVM Verifier Crash: Access Level Trigger

<!--
---
status: CONFIRMED
date: 2026-03-21
toolchain: Swift 6.2.4, Swift 6.4-dev (main-snapshot-2026-03-16)
supports: Research/rawlayout-release-crash-investigation.md
---
-->

## Question

Does the access level of @_rawLayout types affect the LLVM verifier crash under -O?

## Summary

**Yes.** `internal` types build correctly. `public` and `package` types crash. Same source, same module, same file — only the access modifier differs. This is the most targeted reproduction of the bug.

## Results

| Access Level | @_rawLayout + deinit + `-O` | Result |
|--------------|---------------------------|--------|
| `internal` (default) | 1 field, any deinit body | **Builds** |
| `package` | 1 field, empty deinit | **Crash** |
| `public` | 1 field, empty deinit | **Crash** |

Swift 6.3: STILL BROKEN — workaround remains necessary

## Removal Test

This experiment serves as the canary for the compiler fix. When this builds with `public` access under `-O`, the `_deinitWorkaround: AnyObject?` pattern across 22 types in 10 packages can be removed.

```bash
# As-is (internal) — should always pass:
rm -rf .build && swift build -c release

# With public access — passes when compiler is fixed:
sed 's/^struct/public struct/g; s/    init/    public init/g' Sources/main/main.swift > /tmp/test.swift
cp /tmp/test.swift Sources/main/main.swift
rm -rf .build && swift build -c release
git checkout Sources/main/main.swift  # restore
```

## Toolchain Results

| Toolchain | `internal` | `public` |
|-----------|:----------:|:--------:|
| Swift 6.2.4 (Xcode) | Builds | Crash |
| Swift 6.4-dev (2026-03-16) | Builds | Crash |

## Cross-References

- [rawlayout-release-crash-investigation.md](../../Research/rawlayout-release-crash-investigation.md) — consolidated investigation
- [swiftlang/swift#86652](https://github.com/swiftlang/swift/issues/86652) — compiler bug
- Filed as comment: https://github.com/swiftlang/swift/issues/86652#issuecomment-4104543964
