# Swift Issue: CopyPropagation `~Escapable` Coroutine Yield Crash

> **Per-issue restructure: deferred 2026-05-12.** The bug has been fixed
> upstream in Swift 6.3 (Xcode 26.4) — see
> [`swift-institute/Research/swift-compiler-bug-catalog.md`](../../Research/swift-compiler-bug-catalog.md)
> § A2 ("CopyPropagation ~Escapable coroutine yield crash (FIXED in 6.3)").
> The per-issue convention set by sibling
> [`swift-issue-pointer-arithmetic-linux-miscompile/`](../swift-issue-pointer-arithmetic-linux-miscompile/)
> uses `withKnownIssue` to detect upstream fix-landing by flipping red when
> the bug stops firing. Because this bug no longer fires on **any**
> toolchain in the supported matrix (Swift 6.3 stable + 6.4-dev nightly,
> all four platforms), a `withKnownIssue` harness would be permanently red
> with no detection signal. The forensic record below +
> [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) +
> [`PRE-FILING-BUG-REPORT.md`](PRE-FILING-BUG-REPORT.md) carry the audit
> trail; the standalone reproducer at
> [`coenttb/swift-issue-copypropagation-nonescapable-mark-dependence`](https://github.com/coenttb/swift-issue-copypropagation-nonescapable-mark-dependence)
> remains as an external regression-fixture and historical receipt.

**Upstream**: [`swiftlang/swift#88022`](https://github.com/swiftlang/swift/issues/88022) (filed).
**Status**: Bug FIXED in Swift 6.3 (Xcode 26.4). Property.View types in
`swift-property-primitives` re-added `~Escapable` and `@_lifetime(borrow base)`
annotations after the fix landed.
**Reproducer**: Lives in the standalone external repo
[`coenttb/swift-issue-copypropagation-nonescapable-mark-dependence`](https://github.com/coenttb/swift-issue-copypropagation-nonescapable-mark-dependence).
Mirror into this directory as additional `swift-issue-*` SwiftPM test targets
is pending.

## Forensic Record

This subdirectory holds the per-issue forensic notes migrated from
`swift-institute/Research/` on 2026-05-11:

- [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) — Full compiler PR handoff
  (root cause traced via SIL dumps, multi-pass interaction between
  `PredictableDeadAllocationElimination` and `SILCombine`, fix at
  `SimplifyMarkDependence.isRedundant`).
- [`PRE-FILING-BUG-REPORT.md`](PRE-FILING-BUG-REPORT.md) — The pre-filing bug
  report draft (SUPERSEDED 2026-04-02 by
  `swift-institute/Research/noncopyable-ecosystem-state.md`; retained as
  historical rationale for the filing decision).

## Catalog Cross-Reference

See `swift-institute/Research/swift-compiler-bug-catalog.md` § A3
"CopyPropagation ~Escapable coroutine yield crash (FIXED in 6.3)" for the
canonical fix-status entry.
