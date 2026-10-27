# Swift Issue: segfault in applyUnboundGenericArguments for a generic typealias reached through an unbound generic outer type

**Upstream:** **NOT FILED.** This directory is the institute's record.

**Classification:** Type-checker crash. `swift-frontend` dies with signal 11
while resolving a type, so no diagnostic is printed at all.

## Minimal reproducer

`reproducer.swift` (also staged as `Sources/Reproducer/Crash.swift.txt` for the
out-of-process harness):

```swift
struct F<V> { typealias B<U> = U }
func f(_: F.B<Int>) {}
```

```bash
xcrun swiftc -typecheck -swift-version 6 reproducer.swift
```

**Actual** (Apple Swift 6.4.2, macOS 27.2 arm64): exit 139.

```
8.	While evaluating request ResolveTypeRequest(while resolving type , F.B<Int>)
...
4  swift-frontend  ... callback_fn<swift::TypeResolution::applyUnboundGenericArguments(...)::$_0 const>
...
10 swift-frontend  ... swift::TypeChecker::checkGenericArgumentsForDiagnostics(...)
11 swift-frontend  ... swift::TypeResolution::applyUnboundGenericArguments(...)
12 swift-frontend  ... (anonymous namespace)::TypeResolver::applyGenericArguments(...)
```

Full output: `evidence/runs-6.4.2-macos.log`.

**Expected:** no crash. Either the type resolves (`B<U>` does not use `V`, and
a non-generic `typealias B = Int` in the same place is accepted as `F.B`), or the
compiler reports the ordinary error it gives for a nested generic struct in the
same position: `generic parameter 'V' could not be inferred`.

## Trigger characterization

| Ingredient | Removed / replaced by | Result on 6.4.2 |
|---|---|---|
| outer arguments left out (`F.B<Int>`) | `F<Int>.B<Int>` | clean |
| outer type generic (`F<V>`) | `struct F` | clean |
| alias generic (`B<U>`) | `typealias B = Int`, used as `F.B` | clean |
| alias target | `U`, `[U]`, `S<U>`, `S<U, U>`, `S<V>` | all crash |
| outer kind | `enum F<V>`, or the alias in an `extension F` | crash |
| position | function parameter, `let` annotation, `F.B<Int>(0)` expression | all crash |
| `~Copyable` (the original shape) | not needed | crash |
| `extension F.B {}` (no generic arguments) | — | clean |

The crash is in `checkGenericArgumentsForDiagnostics`, called from
`applyUnboundGenericArguments`: the substitution callback is asked for the
outer `V`, which was never given.

## Not the same bug as swift-issue-unbound-generic-typealias-member-lookup

That entry is a rejects-valid error (`'Member' is not a member type of type
'Alias'`) for a member looked up through an unbound generic *alias* as the
base. Here the base is an unbound generic *nominal* type, the member is the
generic alias, and the compiler crashes instead of diagnosing.

## Toolchains

| `swiftc --version` | Result |
|---|---|
| Apple Swift version 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102) | crash, signal 11 (recorded in `evidence/nested-type-generic-escape/Outputs/build-short-forms.txt`) |
| Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1), macOS 27.2 arm64 | crash, exit 139 (run here 2026-10-27) |

Linux and Windows were not run locally; CI covers them. No open-source or
snapshot toolchain has been run, and no upstream duplicate search has been done.

## Workaround

Spell out the outer type's arguments (`F<Int>.B<Int>`), or move the alias to
module scope.

## Harness

`Tests/Reproducer Tests.swift` and `Sources/Reproducer/main.swift` run
`swiftc -typecheck` on `Crash.swift.txt` in a child process, because the source
crashes the compiler. Bug fired = a `Stack dump` that names
`ResolveTypeRequest`. Absent = a clean type-check or an ordinary `error:`. The
crash happens on every toolchain run, so `withKnownIssue` uses `when: { true }`.

## Provenance

Carved out of hypothesis H5 of
`swift-ownership-primitives--nested-type-generic-escape` (`EXPERIMENT.md` line 56,
`Sources/nested-type-generic-escape/main.swift` lines 133-166) in
`swift-institute/Experiments` at commit
`f1c4db4d390c12af5ec454dfb506feaa4ec5e841`. The experiment itself is about a
naming question and stays where it is. Its original H5 shape
(`H5_Foo.Bar<H3_Handle>` with `~Copyable` types) is in
`evidence/h5-shape.swift.txt`; hand-reduced to two lines on 6.4.2.
