# Swift Issue: `@_rawLayout` Element Destruction LLVM IR Domination

> **Per-issue restructure: deferred 2026-05-12.** The minimum reproducer
> for this bug requires ≥3 SwiftPM packages chained through cross-package,
> value-generic `@_rawLayout` storage —
> [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) records 11 simpler
> standalone variants that all PASS, because the bug only manifests with
> the real `Storage<Element>.Inline<capacity>` `@_rawLayout`-backed chain.
> The per-issue convention set by sibling
> [`swift-issue-pointer-arithmetic-linux-miscompile/`](../swift-issue-pointer-arithmetic-linux-miscompile/)
> assumes a single `swiftc`-buildable `Tests/Reproducer.swift` +
> `Sources/Reproducer/main.swift` pair; this bug's surface doesn't fit
> that shape. The forensic record below +
> [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) carry the audit trail;
> a minimal cross-package fixture is still listed as "pending" below.

**Upstream**: [`swiftlang/swift#86652`](https://github.com/swiftlang/swift/issues/86652) (filed for the parent issue family; this is a `~Copyable` value-generic-deinit variant).
**Status**: STILL BROKEN on Swift 6.3.1 — workaround `_deinitWorkaround: AnyObject?` +
field-ordering applied to 36 inline-storage types across 9 packages in
`swift-primitives`.
**Reproducer**: No standalone external repo yet. The workaround is currently
demonstrated by-application across the affected primitives packages; a
minimal SwiftPM reproducer mirrored into this directory as a test target is
pending.

## Forensic Record

This subdirectory holds the per-issue forensic notes migrated from
`swift-institute/Research/` on 2026-05-11:

- [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) — Bug A (deinit body silently
  skipped) + Bug B (automatic member destruction not synthesized) for
  `~Copyable` structs with cross-package, value-generic stored properties
  backed by `@_rawLayout` storage. SUPERSEDED 2026-04-02 by
  `swift-institute/Research/noncopyable-ecosystem-state.md`; retained as
  per-issue historical rationale.

## Catalog Cross-Reference

See `swift-institute/Research/swift-compiler-bug-catalog.md` master fix-status
table row "`@_rawLayout` element destruction LLVM IR domination
(`swiftlang/swift#86652`)" for the canonical entry.
