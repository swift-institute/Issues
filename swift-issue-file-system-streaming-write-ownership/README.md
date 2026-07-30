# `swift-issue-file-system-streaming-write-ownership`

`swift-frontend` aborts (signal 6) at `-O` when the SIL ownership verifier,
run by the **CopyPropagation** pass, finds that the pass shortened the
`begin_borrow`/`end_borrow` scope of a **borrowed `~Copyable` parameter** so
that the `end_borrow` precedes the apply consuming the parameter's projected
`~Copyable` field:

```
Found outside of lifetime use?!
Value:   %6 = begin_borrow %1 : $Context
Consuming User:   end_borrow %6 : $Context
Non Consuming User:   try_apply %15(%5, %13) : $@convention(thin)
        (@guaranteed Span<UInt8>, @guaranteed Descriptor) -> @error InnerError, normal bb3, error bb4
Found ownership error?!
4.  While running pass … SILFunctionTransform "CopyPropagation"
error: compile command failed due to signal 6
```

## Observed / expected

- **Observed** (`swiftc -O Crash.swift`, 6.3-line): abort as above. `-Onone`
  compiles clean. SILGen's raw SIL is well-formed — the `end_borrow`s sit in
  both `try_apply` continuations, after the call; CopyPropagation moves them.
- **Expected**: clean compilation. The borrowed `Context` is live across the
  apply (its `descriptor` field is the call's `@guaranteed` argument).

## Minimal reproduction

Single file, no dependencies (`Sources/Reproducer/Crash.swift.txt`), key shape:

```swift
struct Descriptor: ~Copyable, Sendable { var raw: Int32; deinit {} }
struct Context: ~Copyable, Sendable { var descriptor: Descriptor?; let isAtomic: Bool }

func write(chunk span: borrowing Span<UInt8>, to context: borrowing Context) throws(OuterError) {
    do {
        try writeAll(span, to: context.descriptor!)   // borrowed field projection
    } catch {
        throw OuterError(error)                       // typed-throws error mapping
    }
}
```

Probe:

```sh
swiftc -O Crash.swift -o /dev/null    # aborts on 6.3.3-RELEASE
```

The `try_apply` is **not** load-bearing: a variant returning `Result` through
a plain `apply` still aborted — the trigger is the field-projected nested
borrow scope of the borrowed `~Copyable` value, not the throwing lowering
(see [INVESTIGATION.md](INVESTIGATION.md), "Empirical correction").

## Affected Swift versions (each row `swift --version`-confirmed, macOS arm64, 2026-07-30)

| Toolchain | `swiftc -O` result |
|---|---|
| 6.3.3-RELEASE (swiftly) | **ABORT** — `Found outside of lifetime use?!`, pass `CopyPropagation` |
| Apple Swift 6.4 (Xcode) | clean |
| 6.4.x-snapshot-2026-07-23 (+assertions) | clean |
| main-snapshot-2026-07-11 (+assertions) | clean |

Fixed on the 6.4 line; the snapshots are assertions-enabled builds, so the
clean rows are fix evidence. An earlier record additionally verified clean on
6.5-dev snapshot 2026-05-27 (+assertions).

## Harness

Repository two-target convention: the trigger ships as `Crash.swift.txt` and
is compiled OUT OF PROCESS (`swiftc -O`) because the abort would otherwise
kill the Issues package build on affected toolchains.
`Tests/Reproducer.swift` wraps the probe in `withKnownIssue` VERSION-GATED to
probed-compiler < 6.4; the red flip on a 6.3-line leg is the signal that the
fix (or a backport) reached that line. `Sources/Reproducer/main.swift` is the
standalone probe (exit 1 = bug fired, 0 = clean or inconclusive).

`Sources/Reproducer/Workaround.swift.txt` is the retained passing
counterpart: the same source with `@_optimize(none)` on the crashing
function, which compiles and runs clean. It documents that suppressing the
pass avoids the abort; the shipped production fix was structural instead (see
Workaround below).

## Upstream

**Destination**: `swiftlang/swift`.
**Search (2026-07-30, `"Found outside of lifetime use" CopyPropagation`)**:
8 hits, none this trigger — closest are
[swiftlang/swift#90614](https://github.com/swiftlang/swift/issues/90614)
(open; same pass and message on 6.3.3, but a `load_borrow`ed Copyable
`String` passed as a guaranteed phi from `Optional.map { } ?? .null` — no
`~Copyable` borrow) and
[swiftlang/swift#90408](https://github.com/swiftlang/swift/issues/90408)
(closed completed; a 6.4 regression, opposite version profile — ours is
*fixed* on 6.4). Previously differentiated: #89787 (SILGenCleanup,
enum-case-pattern catch) and #78447 (C-header struct pointers).
**Searched, no exact match — ELIGIBLE to file** (or to contribute as a
data point on #90614 if maintainers judge the family shared); filing remains
principal-gated.

## Workaround

Shipped structural fix in `swift-file-system` (2026-06-30): the
descriptor-projecting throwing helpers moved into `borrowing` methods on the
`~Copyable` context type — inside a `borrowing` method `self` is a
whole-function `@guaranteed` parameter, so there is no nested borrow scope
for CopyPropagation to shorten. Suppression attributes (`@_optimize(none)`,
`-sil-disable-pass=CopyPropagation`) were verified to avoid the abort but
rejected as footguns. The structural fix is correct on all toolchains and
needs no removal on 6.4+.

## Provenance (Institute discovery context)

Surfaced blocking `swift build -c release` of `swift-file-system` (module
`File System Core`, `File.System.Write.Streaming.write(chunk:to:)`), which in
turn blocked `swift-pdf`'s release build. Reduced 2026-06-30 to the
single-file shape above (disproving the earlier belief that WMO +
cross-module inlining were required). Full pipeline-stage analysis,
stale-cache rule-out, duplicate differentiation, and the shipped-fix record:
[INVESTIGATION.md](INVESTIGATION.md). Catalog: bug-catalog §A23 (family §A5).
