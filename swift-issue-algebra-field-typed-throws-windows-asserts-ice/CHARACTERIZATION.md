# `hasErrorResult()` abort on a non-throwing → typed-throws (nested-generic error) conversion in `Algebra.Field` test fixture

> **STAGED terminal record** (not filed upstream — swiftlang filing does not exist as a step per [ISSUE-008] standing policy). `swift-institute/Issues` is the only destination. Sibling of catalog §A20 / §A21 (same +Asserts-only class, different mechanism).

## Classification

**ICE / Crash** — compiler assertion abort (`abort()`, signal 6) during **IR generation** (`IRGenRequest`). Surfaces only on **+Asserts** toolchains; NoAsserts (stock macOS/Linux release) compiles and tests green. The library compiles clean on every platform — only the **test target** crashes.

## Environment

| | |
|---|---|
| **Crashes on** | Swift 6.3 `+Asserts` (Windows CI gating leg, `swift-6.3-windows-toolchain`); reproduced locally on `swiftlang/swift:nightly-6.3-jammy` = Swift **6.3.3-dev** (`c83acbf89dd1298`), `Build config: +assertions`. Also fired the advisory `Ubuntu (Swift main nightly, release)` leg (assertions-enabled nightly, `Types.h:5374`). |
| **Green on** | Swift **6.3.3** release NoAsserts (Apple macOS) — 122 tests pass; `swift:6.3` Linux release. |
| **Config** | `-Onone -g`, the crash is in IRGen of the test file; bare `swiftc` single-file reproducer (no SwiftPM needed). |
| **Real package** | `swift-primitives/swift-algebra-primitives` @ `8fe0381`, target `Algebra Primitives Tests`. |

## Observed

```
swift-frontend: /home/build-user/swift/include/swift/AST/Types.h:5274:
    SILResultInfo &swift::SILFunctionType::getMutableErrorResult(): Assertion `hasErrorResult()' failed.
3.  While evaluating request IRGenRequest(IR Generation for file ".../Algebra.Law Tests.swift")
4.  ... for expression at [Algebra.Law Tests.swift:100:25 - line:100:38] RangeText="{ _ in false "
```

On Windows the same assertion prints as `Assertion failed: hasErrorResult(), file ...\include\swift/AST/Types.h, line 5274`. The crash is pinned to the exact expression `{ _ in false }` at line 100, columns 25–38.

## Root cause

`Algebra.Field<Element>` stores `reciprocal: (Element) throws(Algebra.Field<Element>.Error) -> Element` — a typed-throws function whose error is the **nested-generic** `Field<Element>.Error`. The `brokenReciprocalField` test fixture assigns a **bare non-throwing** closure literal `{ _ in false }` to that parameter (`Field<Bool>`). Passing a non-throwing function where a typed-throws function is expected is a valid subtype conversion, so the compiler inserts a reabstraction thunk. Under +Asserts `-g`, IRGen of that thunk's SIL function type calls `SILFunctionType::getMutableErrorResult()`, which asserts `hasErrorResult()` — but the function type produced for the non-throwing→typed-throws conversion does not carry the error result the assertion expects. `hasErrorResult()` is assertion-gated, so:

- **+Asserts** (Windows 6.3, assertions-enabled nightly): the assert runs → `abort()`.
- **NoAsserts** (stock macOS/Linux release): the assert is skipped → latent → macOS/Linux green.

**Distinct from §A13** (`FunctionSignatureOpts` `SILArgument.cpp:40` assertion): §A13 is an `-O` optimizer crash on a generic *thrown* error left in a function signature; this is an `-Onone -g` IRGen crash on the *non-throwing → typed-throws conversion thunk*. Distinct from §A20/§A21 (mangler / debug-info round-trip on nested-generic *names*); this is the SIL function-type error-result invariant.

## Reproducer

`main.swift` (single file, bare `swiftc`), driven by `build.sh`:

| Toolchain | Result |
|---|---|
| Apple Swift 6.3.3 NoAsserts (host macOS) | **PASS** (`[[ALL-OK]]`) — matches macOS-green |
| `swiftlang/swift:nightly-6.3-jammy` 6.3.3-dev +Asserts | **CRASH** `hasErrorResult()` / `getMutableErrorResult` (`evidence/repro-crash-6.3.3-dev.log`) — matches Windows |

```sh
sh build.sh .                                                                       # host → PASS
docker run --rm -v "$PWD":/w -w /w swiftlang/swift:nightly-6.3-jammy sh build.sh .  # +Asserts → abort
```

**Ingredient model**: a generic struct holding a typed-throws stored closure whose error is the struct's **own nested generic** error type (`Field<Element>.Error`), assigned a **bare non-throwing** closure literal. Spelling the closure's signature explicitly (so it is natively typed-throws, no conversion thunk) removes the trigger; so does a non-generic error type. The `evidence/real-package-crash-6.3.3-dev.log` is the real-package +Asserts abort.

## Resolution — APPLIED & VALIDATED (test-side explicit typed-throws signature)

Spell the closure's typed-throws signature explicitly so no non-throwing→typed-throws conversion thunk is generated — identical behavior (still returns `false`, never throws), and it matches the already-working sibling fixture `Algebra.Field Tests.swift:31`:

```swift
// Algebra.Law Tests.swift:100 — brokenReciprocalField
reciprocal: { (_: Bool) throws(Algebra.Field<Bool>.Error) -> Bool in false }   // was: { _ in false }
```

**Validated** (real-package copy): +Asserts (`swiftlang/swift:nightly-6.3-jammy` 6.3.3-dev) `swift build --build-tests` → `Build complete! (6.80s)`, no assertion; macOS release host `swift test` → **122 tests in 47 suites pass**. Applied to `swift-algebra-primitives` `2b41253` 2026-06-27.

The library's nested-generic typed-throws API (`Field<Element>.Error`, the architecturally correct error shape per [API-NAME-001]/[API-ERR-001]) is unchanged. The library-side alternative (a non-generic error) was rejected as a public-API change made to dodge a compiler bug. Per [ISSUE-008]: terminal dossier (this) + applied workaround; **no upstream filing**. The compiler bug itself is UNFIXED on the 6.3 line — it remains latent-on-+Asserts for any consumer writing the same bare-literal-into-nested-generic-typed-throws pattern.

## Production / evidence

`swift-primitives/swift-algebra-primitives` @ `8fe0381` (pre-fix) → `2b41253` (fix). CI: pre-fix run `28261061739` job `Windows (Swift 6.3, debug)` step `Build` (crash); post-fix run `28280214397` `Windows (Swift 6.3, debug) => success`. Source: `Sources/Algebra Field Primitives/Algebra.Field.swift:36,43,62` (the `reciprocal` typed-throws property/init + nested `Error`), `Tests/Algebra Primitives Tests/Algebra.Law Tests.swift:85-101` (`brokenReciprocalField`, crash at `:100`).

## Source

2026-06-27 swift-algebra-primitives Windows +Asserts investigation (RESOLVE + RECORD; an internal working document).
