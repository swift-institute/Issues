# `[Compiler][Rejects valid] ~Copyable Sequence conformance fails during module emission`

Canonical work item: [swift-institute/Issues#4](https://github.com/swift-institute/Issues/issues/4)

Canonical evidence path: [swift-issue-emit-module-noncopyable-sequence](https://github.com/swift-institute/Issues/tree/main/swift-issue-emit-module-noncopyable-sequence)

This directory is evidence for the canonical GitHub Issue, not a second status ledger.

## Summary

A nested generic container with a compound `~Copyable` constraint, unsafe pointer storage, a conditional `Sequence` conformance, and a borrowing closure in another file is rejected only during module emission.

Expected: the module emits because the conditional conformance restricts `Element` to `Copyable` where required.

Observed on the source-reported Swift 6.2.3 arm64 macOS 26 matrix: module emission reports that `Element` does not conform to `Copyable` at `UnsafeMutablePointer<Element>`.

## Reproduction

From this directory:

```console
swiftc -swift-version 6 -enable-experimental-feature Lifetimes -emit-module -module-name EmitModuleBug Sources/EmitModuleBug/*.swift
```

The source files and manifest are byte-faithful copies from the commit recorded in `evidence/source-provenance.json`. No fresh result is asserted by this staging packet.

Workaround: expose `forEach` instead of `Sequence`, or co-locate borrowing methods where feasible.

Upstream: [swiftlang/swift#86669](https://github.com/swiftlang/swift/issues/86669).

Privacy screen: `PUBLIC_SAFE`.

## Fixed in Swift 6.4 (re-verified 2026-10-11)

Toolchain: Apple Swift 6.4 (swiftlang-6.4.0.34.1), Xcode toolchain, arm64-apple-macosx27.2.

The recorded command, `swiftc -swift-version 6 -enable-experimental-feature Lifetimes -emit-module -module-name EmitModuleBug` over `Sources/Reproducer/*.swift`, exits 0. The `-Repro` target stays as a regression fixture: building the package is the probe. The `forEach`-instead-of-`Sequence` workaround can be retired in the packages that carry it. Closed as fixed; upstream swiftlang/swift#86669.
