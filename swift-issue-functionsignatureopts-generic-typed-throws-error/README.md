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

## CI validation (this entry is wired into the Issues repo CI)

Because the bug aborts the compiler, the crashing source is shipped as a
**resource** (`Sources/Reproducer/Crash.swift.txt`) — compiling it as a normal
target would abort the whole package build. Two harnesses compile it **out of
process** via `swiftc -O` and report the abort:

- `Tests/Reproducer.swift` — Swift Testing harness wrapping the probe in
  `withKnownIssue(...)`. **Green while the bug fires; flips red the moment an
  upstream fix lands** and `Crash.swift.txt` compiles cleanly (the weekly
  `nightly-main-jammy` cron makes the flip visible).
- `Sources/Reproducer/main.swift` — standalone exit-code probe (`exit(1)` bug
  fired / `exit(0)` absent or inconclusive).

The repo CI (`.github/workflows/ci.yml`) enumerates `swift-issue-*/` and runs each
through the canonical `swift-institute` reusable, whose matrix is **Swift 6.3
(macOS / Linux / Windows) + 6.5-dev nightly (Linux, advisory)**. So CI empirically
confirms the crash on the **6.3 stable** pin (= the reported 6.3.2-family
environment) across macOS/Linux/Windows **and** on **6.5-dev** nightly — a *subset*
of the full 6.2 → 6.5-dev matrix above. The **6.2 / 6.2.3** legs are **not** in the
CI matrix; those cells were verified locally (see the correction note above).

## Trigger characterization — verified ingredient list

Each ingredient was independently confirmed necessary (remove it → compiles clean):

| Ingredient | Required? | Control that proves it |
|---|---|---|
| Generic function (`<T>`) | **Yes** | non-generic `func parse(_:Int) throws(MyError<Int>)` → CLEAN |
| Typed-throws error carrying the **abstract** type parameter (`throws(MyError<T>)`) | **Yes** | non-generic error `throws(PlainError)` → CLEAN; **concrete** `throws(MyError<Int>)` → CLEAN |
| ≥1 same-module caller of the generic function | **Yes** | the generic function alone (no caller) → CLEAN |
| `-O` | **Yes** | debug / `-Onone` → CLEAN (FunctionSignatureOpts only runs at `-O`) |
| An **eliminable (dead) argument** (so FunctionSignatureOpts builds a signature-optimized thunk) | **Yes** | a function whose *every* argument (incl. `self`) is genuinely used → CLEAN; the reducer's `_ x: T` is unused; the production `Digit`/`Expect` are empty structs (dead `self`). *(Calibration: FSO may also build the thunk via other signature opts, e.g. owned→guaranteed; not exhaustively tested.)* |

**Not required** (confirmed irrelevant): protocol conformance, a `struct`/nested
type, `inout` parameter, `Sendable`, `@inline(never)`, `-enable-testing`,
`-parse-as-library`, `-enable-default-cmo`, and every experimental/upcoming
feature the production build enables (`SuppressedAssociatedTypes`, `Lifetimes`,
`LifetimeDependence`, `ExistentialAny`, …).

## Toolchain matrix (each cell verified by *running the reducer*; versions `swift --version`-confirmed)

| Swift version | Toolchain | Result | Manifestation |
|---|---|---|---|
| 6.2 | `swift-6.2-RELEASE` | **CRASH** | SIL verifier (asserts off) |
| 6.2.3 | `swift-6.2.3-RELEASE` | **CRASH** | SIL verifier (asserts off) |
| 6.3.1 | `swift-6.3.1-RELEASE` | **CRASH** | `ASSERT(!type.hasTypeParameter())` |
| 6.3.2 | `swift-6.3.2-RELEASE` (current Xcode default) | **CRASH** | same assertion |
| 6.3-dev | `2026-01-07-a`, `2026-01-09-a`, `2026-02-05-a` | **CRASH** | same assertion |
| 6.4-dev | `2026-03-16-a`, `2026-05-07-a` | **CRASH** | same assertion |
| 6.5-dev | `2026-05-12-a`, `swift-latest` | **CRASH** | same assertion |

**Present on every tested toolchain 6.2 → 6.5-dev — NOT a 6.3 regression, and NOT
fixed on the latest 6.5-dev snapshot.** The *manifestation* differs by build: on
6.2 / 6.2.3 (assertions off) the malformed FunctionSignatureOpts SIL is caught by
the **SIL verifier** (`error destination of try_apply must take argument of error
result type` — `$MyError<τ_0_0>` block arg vs `$MyError<T>` try_apply error result);
on 6.3.1+ the *same* malformed SIL is caught earlier by the **always-on
`ASSERT(!type.hasTypeParameter())`** added to `SILArgument` (the `ASSERT` macro
fires even in NDEBUG compiler builds — `include/swift/Basic/Assertions.h`). Typed
throws shipped in 6.0, so the true floor may predate 6.2 (untested — no 6.0/6.1
toolchain installed). "Require Swift 6.4+" does **not** remediate this bug (it
crashes on 6.4-dev and 6.5-dev).

> **Correction note:** an earlier revision of this entry recorded "6.2 / 6.2.3
> CLEAN → regression in 6.3." That was a misclassification — 6.2/6.2.3 were graded
> by grepping for the `hasTypeParameter` assertion text, which those toolchains do
> not emit (they print the verifier message instead). An independent re-investigation
> re-ran the reducer and observed the crash on 6.2/6.2.3. **Do not file "regression
> in 6.3" upstream.**

## Severity — loud build-blocker, NOT a silent miscompile

Verified that no shipped configuration silently miscompiles:

- A full default `-O` build on 6.2 / 6.2.3 / 6.3.1 / 6.3.2 / Xcode-default **never
  produces a binary** — every one aborts (verifier on 6.2/6.2.3, assertion on 6.3+).
- The 6.3+ catch is the **always-on `ASSERT` macro**, which fires even in a
  no-assert/NDEBUG compiler build — so there is no 6.3+ config where it slips past.
- The malformed block argument's type is a bare type parameter (`$MyError<τ_0_0>`)
  with no concrete layout, which IRGen cannot lower — even hypothetically past the
  verifier the failure is a loud IRGen abort, not wrong code.

So this blocks `swift test -c release` (and any `-O` build of an affected module) but
cannot emit a corrupted typed-throws error path. Severity = build-blocker.

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

No exact match found (FSO + `!type.hasTypeParameter()` + `SILArgument.cpp:40` signature). Closest hits, all **distinct**:
- **Our own [`swiftlang/swift#87030`](https://github.com/swiftlang/swift/issues/87030) + its fix [`#88931`](https://github.com/swiftlang/swift/pull/88931) — a DIFFERENT bug; does NOT cover this one.** #87030 is an **IRGen** crash (`getMutableErrorResult` / `Types.h:5174`) triggered by a stored closure field `(T) throws(Error) -> T` + a constrained extension `where T == Concrete`; it is **clean on Swift 6.3.2** and only crashes on 6.5-dev. This FSO crash, by contrast, **crashes on 6.3.2** (where #87030 is clean). #88931 changes `SILGenProlog.cpp` / `SILVerifier.cpp` / `IRGenSIL.cpp` — **not** FunctionSignatureOpts — and this FSO crash still reproduces on 6.5-dev. Same typed-throws-nested-generic-error *family*, different *bug*.
- [`swiftlang/swift#73345`](https://github.com/swiftlang/swift/issues/73345) — assertion `signature || !origType->hasTypeParameter()` but in **SILGen** (`AbstractionPattern.h:529`). Different pass.
- [`swiftlang/swift#81317`](https://github.com/swiftlang/swift/issues/81317) — typed throws + `-enable-testing` crash. This reducer needs neither `-enable-testing` nor a test target.
- [`swiftlang/swift#75430`](https://github.com/swiftlang/swift/issues/75430) — type-inference (front-end), not SIL.
- [`#83597`](https://github.com/swiftlang/swift/issues/83597) / [`#84899`](https://github.com/swiftlang/swift/issues/84899) — release-mode **OwnershipModelEliminator** verifier crashes (load-borrow; parameter packs). Different pass.
- [`#83744`](https://github.com/swiftlang/swift/issues/83744) — `-enable-sil-opaque-values`, a different `SILArgument` assertion (`index < getNumSILArguments()`). Needs a non-default flag.

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
