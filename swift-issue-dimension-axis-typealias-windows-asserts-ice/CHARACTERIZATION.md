# `getMangledName` abort emitting debug info for a named local of a value-generic same-type-constrained typealias (`Axis<N>.*`)

> **STAGED terminal record** (not filed upstream — swiftlang filing does not exist as a step per [ISSUE-008] standing policy). `swift-institute/Issues` is the only destination. Sibling of catalog §A20 (vector) — same +Asserts debug-info-round-trip class, different surface.

## Classification

**ICE / Crash** — compiler assertion abort (`abort()`, signal 6) during **IR generation of debug info** (`IRGenDebugInfo`). Surfaces only on **+Asserts** toolchains; NoAsserts (stock macOS/Linux release) compiles and tests green. The **library compiles clean on every platform** — only the **test target** crashes.

## Environment

| | |
|---|---|
| **Crashes on** | Swift 6.3 `+Asserts` (Windows CI gating leg, `swift-6.3-windows-toolchain`); reproduced locally on `swiftlang/swift:nightly-6.3-jammy` = Swift **6.3.3-dev** (`c83acbf89dd1298`), `Build config: +assertions`. |
| **Green on** | Swift **6.3.3** release NoAsserts (Apple macOS) — 268 tests pass; `swift:6.3` Linux release. |
| **Config** | `-Onone -g`, the crash is in IRGen debug-info emission for the test target. The library target builds clean everywhere. |
| **Real package** | `swift-primitives/swift-dimension-primitives` @ `6939cea`, target `Dimension Primitives Tests`. `Axis<let N: Int>` is from `swift-axis-primitives`. |

## Observed

```
error: compile command failed due to signal 6
Abort: function getMangledName at .../lib/IRGen/IRGenDebugInfo.cpp:1098
Failed to reconstruct type for $s14Axis_Primitive0A0V20Dimension_PrimitivesSiRVz$1_RszlE8Verticalay$1__GD
Please submit a bug report ... and include the crash backtrace.
Pass '-Xfrontend -disable-round-trip-debug-types' to disable this assertion.
```

The failing symbol demangles to `Axis<2>.Vertical` — the value-generic same-type-constrained member typealias (`$..._Rsz...` carries the value-generic requirement; `E8Vertical` is the extension member). The compiler names its own escape hatch. The crash member depends on compile/file ordering: the local docker baseline hit `Axis<2>.Vertical`, the Windows CI run hit `Axis<3>.Depth` (`...E5Depthay$2__GD`) — same bug, the whole `Axis<N>.{Vertical,Depth,Horizontal,Direction,Temporal}` family is affected.

### Stack (the decisive frame)

```
(anonymous namespace)::IRGenDebugInfoImpl::getMangledName(swift::irgen::DebugTypeInfo)        ← IRGenDebugInfo.cpp:1098
(anonymous namespace)::IRGenDebugInfoImpl::getOrCreateType(DebugTypeInfo, llvm::DIScope*)
(anonymous namespace)::IRGenDebugInfoImpl::emitVariableDeclaration(...)
swift::irgen::IRGenDebugInfo::emitVariableDeclaration(...)
```

`emitVariableDeclaration` is the load-bearing frame: the crash is emitting the debug-info type record **for a source variable declaration** whose declared type is the sugared value-generic typealias.

## Root cause

`Axis<let N: Int>` (swift-axis-primitives) gains member typealiases via same-type-constrained extensions in `Dimension_Primitives`:

```swift
extension Axis where N == 2 { public typealias Vertical = Dimension_Primitives.Vertical }   // + N == 3, N == 4
// + Depth (N==3/4), Horizontal (N==2), Direction (N==1..4), Temporal (N==4) siblings
```

A test declares a **named local of the sugared type**: `let v: Axis<2>.Vertical = .downward`. Under `-g`, IRGen emits a debug-info type record for that variable; mangling the value-generic same-type-constrained typealias name yields a symbol the compiler's own round-trip self-check **cannot re-demangle**, so it aborts. The check is assert-gated:

- **+Asserts** (Windows 6.3, `swiftlang/swift:nightly-6.3-jammy`): the round-trip verify runs → `abort()`.
- **NoAsserts** (stock macOS/Linux release): the malformed name is emitted unverified → latent → macOS/Linux green.

**Same class as §A20** (vector): both are +Asserts-only failures of the compiler's own mangled-name round-trip on a deep/value-generic institute construct. §A20 is `Mangler::verify` at **SILGen** on an `@_implements` witness name; this is `getMangledName` at **IRGen debug-info** on a variable's declared type. Distinct from the §A22 algebra bug (SIL function-type error-result invariant on a typed-throws conversion).

## Reproducer

**Canonical (robust) — the real package.** Build the test target on a +Asserts toolchain:

```sh
docker run --rm -v ~/Developer:~/Developer -v /tmp/spm:/root/.swiftpm \
  -v <copy-parent>:/scratch swiftlang/swift:nightly-6.3-jammy \
  sh -c 'cd /scratch/swift-dimension-primitives && swift build --build-tests'
# → Abort: getMangledName / IRGenDebugInfo.cpp:1098   (evidence/real-package-crash-6.3.3-dev.log)
```

**Minimal reduction — NON-FAITHFUL (documented per the brief's fragility warning).** A 2-module bare-`swiftc` reduction (`Axis<let N: Int>` in one module; `Vertical` + `extension Axis where N == 2 { typealias Vertical = … }` + a named local `let v: Axis<2>.Vertical = …` in a second module) **compiles clean on +Asserts** — it does not reproduce. The trigger needs the fuller real-package context (the named local lives in a *third* module — the test target — that imports the typealias from `Dimension_Primitives`, which itself extends `Axis` from `Axis_Primitive`; the cross-module debug reference to the value-generic typealias is what the mangler round-trips). Per the brief, the canonical reproducer is the real-package build above; the reduction boundary is recorded here as a negative result ([ISSUE-026]).

**Ingredient model**: value-generic type `Axis<let N: Int>` + a same-type-constrained member typealias `Axis<N>.X` defined in a separate module + a **named local of that sugared type** in a downstream module + `-g` + a +Asserts toolchain. Remove any one — drop `-g`, annotate with the canonical underlying type, or reference `Axis<N>.X` in expression position (no named local) — and the crash disappears. That last option is the fix.

## Resolution — APPLIED & VALIDATED (test-side expression-position rewrite)

The principal ruled out **both** the compiler-sanctioned flag (`-Xfrontend -disable-round-trip-debug-types` on the test target) **and** removing the typealias family — flags are forbidden, and the `Axis<N>.*` family is domain-complete API to maintain (per [ARCH-LAYER-006]/[ARCH-LAYER-008], consumer count must not drive removal; the typealiases are valid Swift exposing a compiler bug, not an API defect). The only remaining lever is the test code.

The 5 `Axis.* Tests.swift` files were rewritten to reference `Axis<N>.X` in **expression position** instead of as the declared type of a named local:

```swift
// before — named local of the sugared type crashes +Asserts debug-info
let axisVert: Axis<2>.Vertical = .downward
let vert: Vertical = .downward
#expect(axisVert == vert)
#expect(axisVert.opposite == vert.opposite)

// after — expression position; homogeneous `==` still proves the typealias IS Vertical
#expect(Axis<2>.Vertical.downward == Vertical.downward)
#expect(Axis<2>.Vertical.downward.opposite == Vertical.downward.opposite)
```

Expression-position member access yields inferred-**canonical** types (`Vertical`), never the sugared `Axis<2>.Vertical`, so no `emitVariableDeclaration` runs for the troublesome type and `getMangledName` is never called on it. Coverage is preserved: existence (the reference forces the typealias to resolve), identity (homogeneous `==` only compiles if both sides are the same type), every member, and the multi-dimension `Axis<1..4>.Direction` identity. Some `@Test(arguments:)` parameterized tests became explicit per-case `#expect`s, so the `@Test` count drops slightly while assertion coverage is preserved.

**All 5 `Axis.*` typealias SOURCE files are untouched** (the API is fully maintained); no unsafeFlags. **Validated** (real-package copy): +Asserts (`swiftlang/swift:nightly-6.3-jammy` 6.3.3-dev) `swift build --build-tests` → `Build complete! (19.88s)`, no `getMangledName`; macOS release host `swift test` → **268 tests in 65 suites pass**. Applied to `swift-dimension-primitives` `5b940ee` 2026-06-27.

Per [ISSUE-008]: terminal dossier (this) + applied workaround; **no upstream filing**. The compiler bug itself is UNFIXED on the 6.3 line — it remains latent-on-+Asserts for any consumer that declares a named local of an `Axis<N>.*` (or any value-generic same-type-constrained typealias) under `-g`.

## Production / evidence

`swift-primitives/swift-dimension-primitives` @ `6939cea` (pre-fix) → `5b940ee` (fix). CI: pre-fix run `28253640439` job `Windows (Swift 6.3, debug)` (crash on `Axis<3>.Depth`); post-fix run `28280214029` `Windows (Swift 6.3, debug) => success`. Source family: `Sources/Dimension Primitives/Axis.{Vertical,Depth,Horizontal,Direction,Temporal}.swift` (the typealiases, untouched); crash sites were `Tests/Dimension Primitives Tests/Axis.* Tests.swift` named locals. `evidence/real-package-crash-6.3.3-dev.log` is the local +Asserts abort + backtrace.

## Source

2026-06-27 swift-dimension-primitives Windows +Asserts investigation (RESOLVE + RECORD; an internal handoff document).
