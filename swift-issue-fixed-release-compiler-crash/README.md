# Swift Issue: `swift-fixed-primitives` release-config compiler crash (`Mem2Reg`/`SILBitfield`) + an `@_optimize(none)` teardown pitfall

**Status:** **RESOLVED** — both problems below are root-caused, worked around, and verified
green locally (`swift test -c release`, macOS 6.3.2; clean `--scratch-path` build). Fix
committed to `swift-fixed-primitives@main` (`a6be446` + `bc2e6e6`, to be squashed once the
6.3-release CI leg confirms green).

There were **two stacked problems**, the second hidden behind the first and *introduced by the
first's workaround*:

1. **Compiler crash (build-blocker).** `Mem2Reg` → `OSSACompleteLifetime` recursion overflows
   the per-function `SILBitfield` budget (`SILBitfield.h:60`, signal 6) compiling the **test
   functions** under `-O`. Worked around with `@_optimize(none)` on the crash-prone tests.
2. **`@_optimize(none)` + `consume` of a move-only value skips its element `deinit`s** (a
   NoOptimization-in-an-`-O`-build teardown miscompile). This is what made the move-only test
   read `destroyedCount → 0`. Fix: **do not** annotate that test (it does not trigger #1).

> **This supersedes a prior "Issue #2 = release library/compiler teardown miscompile with
> blast radius" reading (see "Issue #2 — corrected" below). That was refuted by experiment:
> the `Fixed`/Buffer/Storage teardown is correct at `-O`; nothing is silently leaking.**

**Filing policy:** per standing policy, **NOT** filed upstream to swiftlang;
`swift-institute/Issues` is the terminal record (`feedback_never_file_upstream_swiftlang`).

---

## ⚠️ Correction (2026-06-26) — the original `#89617` diagnosis was wrong

The first revision of this dossier attributed the crash to `FunctionSignatureOpts` /
`SILArgument.cpp:40` / `!type.hasTypeParameter()` (`swiftlang/swift#89617`, catalog § A13),
claimed an `@_optimize(none)` on `init(count:initializingWith:)` was the effective workaround,
and said the crash "cannot be reproduced locally." **All three were false** — the author
pattern-matched the surface error (`signal 6` compiling `Fixed Tests.swift:38`) without
reading a backtrace.

| | Prior (wrong) | Actual (verified — CI log + local repro) |
|---|---|---|
| SIL pass | `FunctionSignatureOpts` | **`Mem2Reg`** (`StackAllocationPromoter::run` → `OSSACompleteLifetime`) |
| Assertion | `SILArgument.cpp:40` `!type.hasTypeParameter()` | **`SILBitfield.h:60` `endBit <= numCustomBits`** |
| Crashing function | the `count:` initializer | **the `@Test` function** |
| Reproducible locally? | "No" | **Yes — macOS 6.3.2 `swift build/test -c release` reproduces it byte-for-byte** |
| Effective workaround | `@_optimize(none)` on the init | `@_optimize(none)` on the crash-prone **test functions** |

The `count:` init genuinely has the #89617 *shape* (`throws(Fixed<S>.Error)` carries the
abstract parameter), but #89617 **cannot manifest here**: the library has **no same-module
caller** of `init(count:)` (`grep '(count:' Sources/` is empty), and the test module aborts in
`Mem2Reg` first. The inherited init annotation was therefore a no-op for the gating crash and
**has been removed** (`Fixed+Columns.swift` restored to pristine); removing it kept the release
build green (verified). Distinct from § A13 — see the comparison table in that entry.

---

## Issue #1 — the compiler crash (`Mem2Reg` / `SILBitfield` overflow)

- **Package:** `swift-primitives/swift-fixed-primitives` (PUBLIC; was gating-red on this).
- **Gating job:** `CI` → `ci` → **`Ubuntu (Swift 6.3, release)`** matrix leg (run `28230583451`,
  sha `bc06b7b`).
- **Backtrace (CI x86_64-linux **and** local arm64-macOS, identical pass/function/assertion):**
  ```
  Assertion failed: (endBit <= T::numCustomBits &&
    "too many/large bit fields allocated in function"), function SILBitfield at SILBitfield.h:60.
  4. While running pass #… SILFunctionTransform "Mem2Reg" on SILFunction
       "@$s22Fixed_Primitives_Tests…checkedinitpopulateseveryslotpropertieshold…"
       for 'checked init populates every slot; properties hold()' (at Fixed Tests.swift:38:5)
     … OSSACompleteLifetime::analyzeAndUpdateLifetime ⇄ InteriorLiveness::compute recursion …
     … StackAllocationPromoter::run … SILMem2Reg::run …   → signal 6 / fatalError
  ```

### Root cause

`SILBitfield` is a per-`SILFunction` scratch bit allocator with a fixed budget
(`numCustomBits`). `Mem2Reg`'s `StackAllocationPromoter` calls
`OSSACompleteLifetime::completeOSSALifetime`, which walks borrow scopes via `InteriorLiveness`
and **recurses on a deeply nested interior-borrow graph**, allocating `SILBitfield`s as it
descends; past a threshold it overflows. Each `@Test` builds a move-only
`Fixed<Buffer<Storage<Memory.Allocator<Memory.Heap>>.Contiguous<E>>.Linear.Bounded>` and makes
many borrowing accesses; under `-O` the inliner collapses the whole `@inlinable`
~Copyable/generic accessor+init chain into the test function, producing the deep borrow graph.
The crash site is the **test function (the inlining sink)** — the library (`Sources/`) is
release-clean (all 183 modules build before the test target). A SIL-optimizer **scalability**
limit, not a miscompile; the always-on `ASSERT` fires even in NDEBUG compilers → build-blocker,
never silent. Not previously in `swift-compiler-bug-catalog.md` (new entry).

### Workaround (verified)

`@_optimize(none)` on the **5 crash-prone `@Test` functions** keeps the inliner from collapsing
the chain in, so no function overflows the bitfield. `swift build/test -c release` →
`Build complete!`, all tests compile. macOS-release reproduces the crash and the fix; `-Onone`
(plain `swift test`) is clean, which is the only reason a casual `swift test` "looked" fine.
Not a manifest `-Onone` opt-out (`unsafeFlags(["-Onone"])` can taint a flip-ready package for
versioned dependency resolution).

---

## Issue #2 — corrected: `@_optimize(none)` + `consume` skips move-only `deinit`s

Once #1 is worked around, the test target runs and one test fails:

```
✘ "move-only elements live in Fixed and tear down once"
   Expectation failed: (count → 0) == 2     (Fixed Tests.swift)
```

It builds a `Fixed` of two `~Copyable` `Item`s (each `deinit` bumps `Probe`), `consume`s it,
and expects 2 destroys; in release it saw 0.

### Refuted hypothesis (do not act on it)

An intermediate diagnosis read this as a **release library/compiler teardown miscompile**,
"platform-independent, not a `@_optimize(none)` artifact," with **blast radius** across the
shared `Buffer`/`Storage` family ("other public packages may be silently leaking under
release"). The supporting evidence — *both* macOS-release and Linux-release fail, debug clean —
was real but the inference was wrong: **both failed because both had the `@_optimize(none)`
annotation on that test.** The decisive control (release **without** the annotation on that one
test) had not been run.

### Verified root cause ([ISSUE-013] variable isolation)

Removing `@_optimize(none)` from **only** the move-only test:
- it **still compiles** under `-c release` (it has too few inlined accessors to trip #1), and
- the deinits run → **`destroyedCount → 2`**, test passes; **all 6 tests pass**.

| move-only test | `-c release` result |
|---|---|
| `@_optimize(none)` present | ❌ 0 destroys (deinits skipped) |
| `@_optimize(none)` absent | ✅ 2 destroys |

So the missed-deinit is caused **entirely by `@_optimize(none)`**: applying NoOptimization to a
function that `consume`s a `~Copyable`-with-`deinit` value, inside an otherwise `-O` module,
elides the element `deinit`s. The `Fixed`/Buffer/Storage teardown is **correct at `-O`** (the
unannotated test proves it) — **there is no library leak and no blast radius.** This is a
narrow, real compiler bug in the NoOptimization-in-an-`-O`-build mode (worth a catalog note),
but for `fixed` the fix is purely: **never annotate a deinit-observing test.**

### Fix

`@_optimize(none)` on the 5 `Int`-element tests (Issue #1); the move-only test is **left
unannotated** (it needs neither workaround). The test footer documents both bugs and warns
against re-annotating any deinit-observing test. Verified: `swift test -c release` → all 6 pass.

---

## Verification status

- Issue #1 crash: reproduced locally (macOS 6.3.2 `swift build --build-tests -c release`),
  byte-identical pass/function/assertion to CI run `28230583451`.
- Issue #1 + #2 fix: `swift test -c release` (clean `--scratch-path`) → `Build complete!` +
  **6/6 tests pass**.
- CI: commit `bc2e6e6`, run `28243845222` — confirming the `Ubuntu (Swift 6.3, release)` leg
  flips green (the gate for this dossier).

> **Out of scope (pre-existing on `bc06b7b`, unrelated to this fix):** the same runs' Embedded
> Wasm (`signal 11`, `MandatoryPerformanceOptimizations` — see
> `Issues/swift-issue-embedded-wasm-mandatory-perf-crash`), Android SDK, and the two
> `Swift main nightly` legs (a `swift-storage-primitives` `noncopyable 'Self.Element' must
> specify ownership` source error the nightly toolchain's stricter checking rejects) are
> independent failures. They were red before this work and keep the aggregate `ci-ok` red; they
> are NOT the compiler-crash this dossier addresses.

## Applied fix (committed)

`swift-fixed-primitives@main`:
- `a6be446` — `@_optimize(none)` on the `@Test` functions (Issue #1).
- `bc2e6e6` — drop it from the move-only test + footer documenting both bugs (Issue #2).
- `Fixed+Columns.swift` restored to pristine (the inherited `#89617` init annotation removed).
- To be squashed into one clean commit once the 6.3-release leg is confirmed green.

## Catalog

- New entry: **Issue #1** — `Mem2Reg`/`OSSACompleteLifetime`/`SILBitfield.h:60` per-function
  bitfield overflow from `@inlinable` ~Copyable/generic inlining into a test function (distinct
  from § A13/#89617).
- New entry: **Issue #2** — `@_optimize(none)` + `consume` of a `~Copyable`-with-`deinit` value
  in an `-O` module elides the element `deinit`s (NoOptimization-mode teardown miscompile).

## Provenance

2026-06-26. Two sessions converged on Issue #1 (both correcting the `#89617` misdiagnosis from
real backtraces — one via Docker `swift:6.3`, one via macOS-release). This session's
variable-isolation experiment resolved Issue #2 and **refuted** the library-teardown/blast-radius
hypothesis. No upstream filing (standing policy).
