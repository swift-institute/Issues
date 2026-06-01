# Swift Issue: FunctionSignatureOpts asserts on a generic function with a generic typed-throws error type

**Upstream:** NOT YET FILED. Standalone single-file `swiftc -O` reducer is ready ([ISSUE-002] gold standard); filing pending principal authorization. Closest existing reports are **distinct** (see *Duplicate search* below).

**Classification:** ICE / compiler crash (signal 6, assertion failure) in the SIL optimizer.

A generic function whose **typed-throws error type is parameterized by the
function's own generic parameter** — `func f<T>(…) throws(E<T>) -> R` — crashes
the optimizer at `-O` when the same module also contains a caller of `f`. The
`FunctionSignatureOpts` pass builds a signature-optimized clone of the generic
function and tries to create a `SILArgument` (for the indirect typed-error
result) whose type `E<T>` still contains the unsubstituted abstract type
parameter `T`, tripping the `!type.hasTypeParameter()` invariant.

## Exact crash signature

```
Assertion failed: (!type.hasTypeParameter()), function SILArgument at SILArgument.cpp:40.
…
4.  While running pass #N SILFunctionTransform "FunctionSignatureOpts"
    on SILFunction "@$s…5parseys5UInt8VxAA7MyErrorOyxGYKlF".
5.  Assertion failed: (!type.hasTypeParameter()), function SILArgument at SILArgument.cpp:40.
…
8   swift-frontend  swift::SILArgument::SILArgument(…)
9   swift-frontend  swift::FunctionSignatureTransform::createFunctionSignatureOptimizedFunction() + 2952
10  swift-frontend  swift::FunctionSignatureTransform::run(bool) + 744
11  swift-frontend  (anonymous namespace)::FunctionSignatureOpts::run() + 1788
```

## Minimal reproducer

`reproducer.swift` (3 declarations), built with **bare `swiftc -O`** (no SwiftPM,
no flags, no features):

```swift
public enum MyError<T>: Swift.Error { case fail }
public func parse<T>(_ x: T) throws(MyError<T>) -> UInt8 { throw .fail }
public func run<T>(_ x: T) -> UInt8 { do { return try parse(x) } catch { return 0 } }
```

```
swiftc -O reproducer.swift -c -o /tmp/x.o     # signal 6
```

## Trigger characterization — verified ingredient list

Each ingredient was independently confirmed necessary (remove it → compiles clean):

| Ingredient | Required? | Control that proves it |
|---|---|---|
| Generic function (`<T>`) | **Yes** | non-generic `func parse(_:Int) throws(MyError<Int>)` → CLEAN |
| Typed-throws error carrying the **abstract** type parameter (`throws(MyError<T>)`) | **Yes** | non-generic error `throws(PlainError)` → CLEAN; **concrete** `throws(MyError<Int>)` → CLEAN |
| ≥1 same-module caller of the generic function | **Yes** | the generic function alone (no caller) → CLEAN |
| `-O` | **Yes** | debug / `-Onone` → CLEAN (FunctionSignatureOpts only runs at `-O`) |

**Not required** (confirmed irrelevant): protocol conformance, a `struct`/nested
type, `inout` parameter, `Sendable`, `@inline(never)`, `-enable-testing`,
`-parse-as-library`, `-enable-default-cmo`, and every experimental/upcoming
feature the production build enables (`SuppressedAssociatedTypes`, `Lifetimes`,
`LifetimeDependence`, `ExistentialAny`, …).

## Toolchain matrix (versions verified via `swift --version`)

| Swift version | Toolchain | Result |
|---|---|---|
| 6.2 | `swift-6.2-RELEASE` | CLEAN |
| 6.2.3 | `swift-6.2.3-RELEASE` | CLEAN |
| 6.3.1 | `swift-6.3.1-RELEASE` | **CRASH** |
| 6.3.2 | `swift-6.3.2-RELEASE` (current Xcode default) | **CRASH** |
| 6.3-dev | `2026-01-07-a`, `2026-01-09-a`, `2026-02-05-a` | **CRASH** |
| 6.4-dev | `2026-03-16-a`, `2026-05-07-a` | **CRASH** |
| 6.5-dev | `2026-05-12-a`, `swift-latest` | **CRASH** |

**Regression introduced in 6.3** (6.2.x is clean) and **NOT fixed on the latest
6.5-dev snapshot.** This is the critical contrast with the Tagged-metadata
family (catalog §A9), which *is* fixed on 6.4-dev — "require Swift 6.4+" does
**not** remediate this bug.

## Production manifestation

`swift-parser-primitives`, `swift test -c release`, compiling the test target
`Parser_Take_Primitives_Tests`:

```
While running pass #168656 SILFunctionTransform "FunctionSignatureOpts"
  on SILFunction "@$s28Parser_Take_Primitives_Tests5DigitV5parseys5UInt8VxzAC5ErrorOyx_GYKF"
  for 'parse(_:)' (at .../Tests/Parser Take Primitives Tests/Parser.Builder Tests.swift:29:5)
```

`Digit<Input>.parse(_: inout Input) throws(Digit<Input>.Error) -> UInt8` is the
production shape — note `Digit<Input>.Error` is *accidentally* generic (it is a
non-payload enum nested in the generic `Digit<Input>`; it never uses `Input`).
The package's `Sources/` targets release-compile clean (55 source modules built
before the crash); the crash is confined to the **test target** (the
`Parser.Builder Tests.swift` parser fixtures — `Digit`, `Expect`, … — share the
generic-typed-throws-error shape).

## Distinct from neighbouring catalog entries

- **§A8** (same *file*, different bug): a type-checker "failed to produce
  diagnostic" ICE on `Parser.Builder`-style opaque returns, in **debug**, **fixed
  on 6.5-dev**. This entry is a **SIL-optimizer** assertion, in **release/-O**,
  **not fixed** on 6.5-dev.
- **§A9** (Tagged-metadata family): a **runtime** `swift_getTypeByMangledName`
  SIGSEGV requiring `SuppressedAssociatedTypes`, **fixed on 6.4-dev**. This entry
  is a **compile-time** assertion requiring **no** experimental features and is a
  **regression since 6.3**, unfixed on 6.5-dev.

## Workarounds (all validated on 6.3.2)

| Workaround | Result | Notes |
|---|---|---|
| `@_optimize(none)` on the **crashing function** (`parse`) | CLEAN | FunctionSignatureOpts skips it. Must be on the function itself… |
| `@_optimize(none)` on the **caller** (`run`) only | **CRASH** | …putting it on the caller does NOT help. |
| Hoist the error type to a **non-generic** type | CLEAN | The production `Digit.Error` doesn't use `Input`; moving it out of the generic context makes the typed-throws error non-generic. Behaviour-preserving. |
| "Require Swift 6.4+" | **does NOT help** | bug is live on 6.4-dev and 6.5-dev. |

## Duplicate search ([ISSUE-007])

No exact match found. Closest hits, all **distinct**:
- [`swiftlang/swift#73345`](https://github.com/swiftlang/swift/issues/73345) — assertion `signature || !origType->hasTypeParameter()` but in **SILGen** (`AbstractionPattern::initSwiftType`, `AbstractionPattern.h:529`), 6.0-dev/Windows. Different pass.
- [`swiftlang/swift#81317`](https://github.com/swiftlang/swift/issues/81317) — typed throws + `-enable-testing` crash. This reducer does **not** need `-enable-testing`.
- [`swiftlang/swift#75430`](https://github.com/swiftlang/swift/issues/75430) — type-inference (front-end), not SIL.

## Disposition — PENDING PRINCIPAL DECISION

Per the investigation brief, the source-side fix is **held for principal
decision** (no autonomous source workaround / toolchain-floor change). Options:

1. **File upstream** (reducer is filing-ready) + accept that `swift test -c
   release` is broken for affected packages until a fix lands. Note "require
   6.4+" is NOT a remedy here.
2. **Source restructure** (behaviour-preserving): hoist the accidentally-generic
   `Digit.Error` (and sibling fixtures' errors) out of the generic context so the
   typed-throws error type is non-generic.
3. **Localized guard**: `@_optimize(none)` on each affected `parse` (test
   fixtures), or exclude the affected test target from release builds.

## Provenance

2026-06-01 parser release-config SIL-crash investigation (`/issue-investigation`).
Catalog entry: `swift-institute/Research/swift-compiler-bug-catalog.md` § A13.
