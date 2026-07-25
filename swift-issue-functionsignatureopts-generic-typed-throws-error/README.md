# Swift Issue: FunctionSignatureOpts asserts on a generic function with a generic typed-throws error type

**Upstream:** **FILED — [swiftlang/swift#89617](https://github.com/swiftlang/swift/issues/89617)** (2026-06-02). Standalone single-file `swiftc -O` reducer per the [ISSUE-002] gold standard. Closest existing reports are **distinct** (see *Duplicate search* below).

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

**Expected:** compiles cleanly (exit 0).

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
environment) across macOS and Linux **and** on **6.5-dev** nightly (the Windows leg is a
no-op — the harness probe is POSIX-only and `#else`-skips Windows) — a *subset*
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

### Additional production manifestations (`Sources/`-level, whole-module release aborts)

Beyond the test-target hit above, this bug has surfaced four times at library `Sources/`
level — i.e. every consumer's `-c release` of the affected graph aborts. **All four are now
fixed** (status re-verified 2026-07-25):

- **`swift-iso-8601`** — `ISO_8601.DateTime.Parse.parse` (four `<Domain>.Parse.Error`
  enums phantom-nested in generic `Parse<Input>`). **Fixed 2026-06-29** by de-phantoming
  the error enums to module scope (`aa1c557..8ad787e`).
- **`swift-w3c-xml`** — `W3C_XML.Lexer.lexDoctype(startPos:)` (phantom-generic
  `Lexer<…>.Error`), CI-surfaced 2026-07-06 on **6.3.3-RELEASE**, Linux x86_64
  `-c release -enable-default-cmo`; macOS debug clean. **Pre-existing** (failed before the
  unrelated ownership-shared rename respell) and **transitively** in consumer `swift-xml`.
  Evidence: CI run
  [28802981666](https://github.com/swift-w3c/swift-w3c-xml/actions/runs/28802981666).
  **Fixed** in `da14353` — `Lexer`'s phantom `Error` hoisted to module-scope
  `__W3CXMLLexerError`, same playbook as iso-8601; landed and pushed. *(This entry read
  "Open" until 2026-07-25; it had in fact been closed earlier. Only a phantom
  `Lexer<Input>.State` remains, which is not an error type and is not used in typed throws.)*
- **`swift-rfc-9110`** — `RFC_9110.Parse.QuotedString.parse` (five phantom-generic parser
  error enums: `Parse.Token`, `Parse.QuotedString`, `Parse.QualityValue`, `Parse.Parameter`,
  `MediaType.Parser`). Assertion at pass `FunctionSignatureOpts` **#568261**, SILFunction
  `@$s8RFC_9110AAO5ParseO12QuotedStringV5parseySay14Byte_Primitive0F0VGxzAF5ErrorOy__x_GYKF`
  — the mangled `@error` carries `<Input>` as `AF5ErrorOy__x_G`. **Found 2026-07-25 by a
  fleet-wide shape scan, NOT by CI** — it was crashing unreported, with 6 direct consumers
  (`swift-http-standard`, `swift-media-type-standard`, `swift-rfc-9112`, `swift-rfc-9111`,
  `swift-rfc-8288`, `swift-rfc-6797`). **Fixed** by hoisting all five to module scope
  (`__HTTPTokenParserError`, `__HTTPQuotedStringParserError`, `__HTTPQualityValueParserError`,
  `__HTTPParameterParserError`, `__HTTPMediaTypeParserError`), each parser keeping a public
  `typealias Error` so the old spelling still resolves. `Parameter` composes `QuotedString`'s
  hoisted error directly, as iso-8601's `Interval` does. A/B on the same command: before, the
  assertion above; after, `Build complete (41.03s)`, 186 tests in 13 suites passing.

- **`swift-rfc-7519`** — `RFC_7519.JWT.Parse._expectPeriod(_:)` (phantom-generic
  `Parse<Input>.Error`: a two-case enum nested in generic `Parse<Input>` that never uses
  `Input`, reached via `typealias Failure = RFC_7519.JWT.Parse<Input>.Error`), CI-surfaced
  2026-07-25 on **6.3.3** Linux x86_64 `-c release -enable-default-cmo`, pass
  `FunctionSignatureOpts` #60289. Surfaced in the **consumer** `swift-foundations/swift-server-foundation`
  (run [30142366879](https://github.com/swift-foundations/swift-server-foundation/actions/runs/30142366879),
  job 89638021488), which is how the RFC_7519 frame reaches an arc build. **Fixed
  2026-07-25** — `Parse`'s phantom `Error` hoisted to module-scope `__JWTParserError`, with
  a public `typealias Error` preserving `Parse<Input>.Error` for consumers (no public API
  break; the sole consumer, `swift-json-web-token`, names `JWT.Parse` nowhere). Verified on
  the real crash configuration by CI run
  [30146494176](https://github.com/swift-ietf/swift-rfc-7519/actions/runs/30146494176):
  **Ubuntu (Swift 6.3, release) green**, both nightly axes green, `ci-ok` green — with
  `Compiling RFC_7519` ×4 freshly compiled and zero assertion/stack-dump markers in the leg
  log. Reproduction + fix both **validated locally**
  2026-07-25 (issue investigation): the production shape
  (`struct Parse<Input>` + nested phantom `Error` + `throws(Failure)` member + same-module
  caller) crashes with this exact assertion on macOS 6.3.3-RELEASE **and** Linux x86_64
  under `-O -enable-default-cmo`; hoisting `Error` to non-generic module scope compiles
  clean on both. Source: `swift-rfc-7519/Sources/RFC 7519/RFC_7519.JWT.Parse.swift`
  (`struct Parse` :16, `enum Error` :37, `typealias Failure` :44, `_expectPeriod` :74,
  same-module callers :49/:51).
  > Attribution note: the arc CI log lists `Compiling Serializer_Fail_Primitives` /
  > `Parser_Fail_Primitives` shortly before the abort, but those are ordinary
  > build-progress lines for modules that compiled **clean** — `swift-primitives` is not
  > implicated. The crashing frame is `RFC_7519`. Do not re-attribute this to the
  > parser/serializer `Fail` primitives.

### ⚠️ Shape is necessary but NOT sufficient — do not read the watchlist as a damage report

Measured 2026-07-25. A fleet-wide structural scan — 3,092 packages,
51,500 `.swift` files, all 34 institute roots — found **326 instances of the phantom shape,
102 of them reachable as typed throws**. Release-building a sample settled what that means:

| package | shape | `swift build -c release` |
|---|---|---|
| `swift-rfc-9110` | 5 instances | **ICE** (now fixed) |
| `swift-rfc-2045` | 3 instances | **clean** |
| `swift-rfc-5322` | 2 instances | **clean** |

`swift-rfc-2045` carries the *byte-identical* shape to `swift-rfc-7519` pre-fix — nested
non-payload `Error` in a generic `Parse<Input>`, `typealias Failure = …Parse<Input>.Error`,
`Parser.Protocol` conformance — and compiles fine. So the **second precondition in the table
above (an eliminable/dead argument, letting FSO build the signature-optimized thunk) is
load-bearing**, not incidental.

Consequences for anyone working this class:

- **The shape census is a CANDIDATE list, not a crash list.** "Shape present" is never
  "broken". 1 of 3 sampled crashed.
- **The only reliable test is a release build** (~1–2 min per package). Cheaper than
  de-phantoming ~50 latent sites that compile correctly today.
- **`Digit<Input>.Error` in `swift-parser-primitives` is already fixed** — hoisted to
  module-scope `__DigitError` with `extension Digit { typealias Error = __DigitError }`.
  It is listed above as the original reducer site; it is not an open item.

Remaining latent candidates (shape present, unbuilt, **not** known broken): `swift-rfc-2822`
(2), `swift-rfc-2183`, `swift-rfc-2369`, `swift-rfc-5321`, `swift-rfc-6068`, `swift-rfc-7617`,
`swift-rss-standard`; and outside the spec family `swift-property-primitives` (17),
`swift-io-primitives` (10, mostly `Experiments/`), `swift-pool-primitives` (7),
`swift-async-primitives` (4), `swift-binary-cursor-primitives` (3), `swift-vector-primitives`
(3), `swift-serializer-primitives` (2), `swift-heap-primitives` (2), `swift-http-body` (2),
`swift-w3c-svg` (2), plus singles elsewhere.

**Scan limits, stated so the numbers are read correctly.** No lint rule exists for this shape,
so the scan was a purpose-built structural scanner (brace-walking, qualified-name resolution),
controlled against every known positive and every known fix before use. It was wrong twice
during development, both times *under*-reporting: (1) it missed transitively-phantom enums
whose cases reference *other* phantom enums — how iso-8601's `Interval`/`RecurringInterval`
hid; (2) simple-name resolution either invented 14 false positives on
`swift-parser-primitives`' `public enum Parser {}` namespace or, when that was "fixed" by
letting non-generic declarations win, dropped **both** positive controls to zero, because
`swift-rfc-7519` declares both a namespace `RFC_7519.Parse` and a generic
`RFC_7519.JWT.Parse<Input>`. Qualified-name resolution was the fix. Ground truth is **n=4
release builds, macOS arm64 only**; the scanner is source-structural and therefore blind to
macro-generated code, and it over-approximates typed-throws reachability by owner-name match.

**A lint rule would close this class properly** — catching the shape at author time rather
than at release-build time, which is the only reason `swift-rfc-9110` went undetected while
crashing.

Full manifestation history + latent-sibling watchlist: catalog **§ A13** manifestations (2)/(3).
The `swift-rfc-7519` manifestation above is recorded here only — catalog **§ A13** has **not**
yet been extended with it (that file lives in the PUBLIC `Research/` tree; updating it is a
separate, deliberate edit).

## Distinct from neighbouring catalog entries

- **§A8** (same *file*, different bug): a type-checker "failed to produce
  diagnostic" ICE on `Parser.Builder`-style opaque returns, in **debug**, **fixed
  on 6.5-dev**. This entry is a **SIL-optimizer** assertion, in **release/-O**,
  **not fixed** on 6.5-dev.
- **§A9** (Tagged-metadata family): a **runtime** `swift_getTypeByMangledName`
  SIGSEGV requiring `SuppressedAssociatedTypes`, **fixed on 6.4-dev**. This entry
  is a **compile-time** assertion requiring **no** experimental features, is
  **present since ≥6.2 (not a 6.3 regression)**, and is unfixed on 6.5-dev.

## Workarounds (all validated on 6.3.2)

| Workaround | Result | Notes |
|---|---|---|
| `@_optimize(none)` on the **crashing function** (`parse`) | CLEAN | FunctionSignatureOpts skips it. Must be on the function itself… |
| `@_optimize(none)` on the **caller** (`run`) only | **CRASH** | …putting it on the caller does NOT help. |
| Hoist the error type to a **non-generic** type | CLEAN | The production `Digit.Error` doesn't use `Input`; moving it out of the generic context makes the typed-throws error non-generic. Behaviour-preserving. |
| "Require Swift 6.4+" | **does NOT help** | bug is live on 6.4-dev and 6.5-dev. |

## Duplicate search ([ISSUE-007])

No exact match found (FSO + `!type.hasTypeParameter()` + `SILArgument.cpp:40` signature). Closest hits, all **distinct**:
- **Our own [`swiftlang/swift#87030`](https://github.com/swiftlang/swift/issues/87030) + its fix [`#88931`](https://github.com/swiftlang/swift/pull/88931) — a DIFFERENT bug; does NOT cover this one.** #87030 is an **IRGen** crash (`getMutableErrorResult` / `Types.h:5174`) triggered by a stored closure field `(T) throws(Error) -> T` + a constrained extension `where T == Concrete`; it is **clean on Swift 6.3.2** and only crashes on 6.5-dev. This FSO crash, by contrast, **crashes on 6.3.2** (where #87030 is clean). #88931 (open, unmerged) changes SILGen / the SIL verifier — **not** FunctionSignatureOpts — and this FSO crash still reproduces on 6.5-dev. Same typed-throws-nested-generic-error *family*, different *bug*.
- [`swiftlang/swift#73345`](https://github.com/swiftlang/swift/issues/73345) — assertion `signature || !origType->hasTypeParameter()` but in **SILGen** (`AbstractionPattern.h:529`). Different pass.
- [`swiftlang/swift#73641`](https://github.com/swiftlang/swift/issues/73641) — near-identical *title* ("compiler crash when using typed throws of an enum nested within a generic type") but a **closed**, Swift-6.0-era **SILGen** crash (`emitThrow`, `SILGenStmt.cpp:1634`, assertion `destErrorType == SILType::getExceptionType(...)`). Different pass, different site, already fixed — not this `-O` FunctionSignatureOpts crash. (Pre-empts the most likely "isn't this a duplicate?" challenge given the title overlap.)
- [`swiftlang/swift#88959`](https://github.com/swiftlang/swift/issues/88959) — **closest relative by mechanism**: also typed throws with a generic-bearing error, but a **`-Onone` (debug)** crash whose trigger is a **protocol requirement** whose error references an **associated type** (`func f() throws(EFoo<T>)`), with a conformer concretizing it. This crash is **`-O`-only in FunctionSignatureOpts** (which does not run at `-Onone`) and needs **no protocol / associated type** — a free generic function suffices. Same family, different pass / optimization level / trigger.
- [`swiftlang/swift#80732`](https://github.com/swiftlang/swift/issues/80732) — `async` + primary-associated-type + existential return with a **non-generic** error (`throws(MyError)`). A non-generic error is **clean** here (ingredient-control #2), so distinct.
- [`swiftlang/swift#77612`](https://github.com/swiftlang/swift/issues/77612) — runtime **SIGSEGV** (EXC_BAD_ACCESS) with a **non-generic class** error in a protocol/generic-class context — not a compile-time FunctionSignatureOpts assertion. Distinct.
- [`swiftlang/swift#81317`](https://github.com/swiftlang/swift/issues/81317) — typed throws + `-enable-testing` crash. This reducer needs neither `-enable-testing` nor a test target.
- [`swiftlang/swift#75430`](https://github.com/swiftlang/swift/issues/75430) — type-inference (front-end), not SIL.
- [`#83597`](https://github.com/swiftlang/swift/issues/83597) / [`#84899`](https://github.com/swiftlang/swift/issues/84899) — release-mode **OwnershipModelEliminator** verifier crashes (load-borrow; parameter packs). Different pass.
- [`#83744`](https://github.com/swiftlang/swift/issues/83744) — `-enable-sil-opaque-values`, a different `SILArgument` assertion (`index < getNumSILArguments()`). Needs a non-default flag.

## Disposition — FILED upstream

**Filed as [swiftlang/swift#89617](https://github.com/swiftlang/swift/issues/89617)** on 2026-06-02,
after two independent fresh-eyes reviews and a live duplicate re-check. The CI `withKnownIssue`
harness tracks #89617 and will flip red when an upstream fix lands.

Source-side remediation of the affected package (`swift-parser-primitives`) is a **separate concern
owned by that package's session**; behaviour-preserving options remain: (1) hoist the
accidentally-generic `Digit.Error` (and sibling fixtures) out of the generic context so the
typed-throws error type is non-generic; (2) `@_optimize(none)` on each affected leaf `parse`, or
exclude the test target from release builds. "Require Swift 6.4+" is NOT a remedy (live on 6.4-dev/6.5-dev).

## Provenance

2026-06-01 parser release-config SIL-crash investigation (`/issue-investigation`).
Catalog entry: `swift-institute/Research/swift-compiler-bug-catalog.md` § A13.
