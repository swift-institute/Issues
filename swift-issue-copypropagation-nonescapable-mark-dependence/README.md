# Swift Issue: CopyPropagation `~Escapable` Coroutine Yield Crash

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
