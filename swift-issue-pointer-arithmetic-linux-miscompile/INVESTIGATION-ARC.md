# Investigation Arc: Linux Release Pointer-Arithmetic Miscompile

**Status**: Toolchain defect confirmed via independent `/collaborative-discussion`
convergence (2026-05-11). Known issue
[`swiftlang/swift#77558`](https://github.com/swiftlang/swift/issues/77558)
(filed 2024-11-12). **Fixed on Swift 6.4-dev nightly-main**, awaiting backport
or 6.4 release. Original [ISSUE-001] upstream-search keyword set missed this —
see "Convergence outcome" below for blind-spot analysis.

**Tracking artifact**: `swift-institute/Issues/swift-issue-pointer-arithmetic-linux-miscompile/`

This note captures the **investigation arc**, including the false trails. The
test-target catalog in the Issues repo still carries the artifacts of those
false trails (16 SwiftPM test targets), preserved as institutional record. The
final filing-ready 8-line reproducer is in
`Issues/.../UPSTREAM-DRAFT.md`.

## Why this note exists

The bug's surface is non-obvious. The investigation visited three sequential
hypotheses, each refuted by the next experiment, before landing on the actual
characterization. Future bug hunts on this codebase will benefit from the
correction trail; the 16-target SwiftPM structure in the Issues repo looks
overengineered without this context.

## Confirmed bug shape (current understanding)

- **Where**: LLVM optimization or backend codegen (SIL and LLVM IR are byte-identical between affected and unaffected source forms).
- **Affected**: Swift 6.3.1 release + 6.4-dev nightly, `-O` and `-Osize`, both macOS arm64 and Linux x86_64 (cross-platform, not Linux-only).
- **Unaffected**: `-Onone` on any platform.
- **Trigger**: at least two chained `.advanced(by:)` calls on `UnsafeMutablePointer<Int>` where at least one offset is negative.
- **Does NOT depend on**: any SwiftPM `swiftSettings`, the `unsafe` keyword (SE-0466), user-authored operator overloads, any of `.strictMemorySafety`, `.Lifetimes`, `.LifetimeDependence`, or any other experimental/upcoming feature.

## Investigation arc — chronological

### Round 0 — original failure surface (2026-05-11 morning)

`swift-affine-primitives` Linux 6.3 release CI red on `unsafeMutablePointerMinusTypedOffset` test. Test used a user-authored `-` operator wrapping `.advanced(by: -Int(bitPattern: rhs))`. Three operator-body fixes attempted, all failed (explicit local `let`, `@inlinable` swap, `withExtendedLifetime` wrapping). Concluded the miscompile is at the call-site `.pointee` read, not in the operator body.

### Round 1 — `.Lifetimes` hypothesis (FALSE)

After moving the reproducer to a standalone repo and bisecting the 10 swiftSettings affine-primitives enabled, the single setting `.enableExperimentalFeature("Lifetimes")` appeared to be the unique trigger. The 11-target sweep confirmed all 11 With\*-feature targets failed equally, and only the WithoutUnsafe target (with no `unsafe` keyword markers) passed.

**False conclusion**: `.Lifetimes` is the trigger.
**Refutation**: when source files received `unsafe` markers in the byte-identical sweep, ALL 11 targets failed — including the Control target with zero swiftSettings.

### Round 2 — `unsafe` keyword hypothesis (FALSE)

Adding a `WithoutUnsafe` disambiguator target proved that the `unsafe` keyword marker (not `.Lifetimes`) was the common factor across all failing configurations in the prior round. Reported as the trigger.

**False conclusion**: the Swift 6.3 `unsafe` keyword expression (SE-0466) is the trigger.
**Refutation**: standalone `swiftc -O` on the 8-line reproducer fires the bug regardless of `unsafe` markers — on macOS AND Linux. SIL and LLVM IR are byte-identical between with-unsafe and without-unsafe forms. The `unsafe` attribution was an artifact of SwiftPM test-framework build flags happening to gate which configurations expose the optimizer bug under `swift test -c release`.

### Round 3 — actual characterization (CONFIRMED)

Standalone reproducer extraction. SIL diff (byte-identical) + LLVM IR diff (byte-identical) + optimization-level matrix (-O / -Osize fail, -Onone passes) + cross-platform check (macOS arm64 + Linux x86_64 both fail at standalone -O). Reduction by trigger-surface variation:

- Single `.advanced(by:)` step: passes.
- Subscript `buf[2]`: passes.
- Two `.advanced(by:)` calls, both positive: passes.
- Two `.advanced(by:)` calls, at least one negative: **FAILS**.

**Confirmed**: chained mixed-direction pointer arithmetic on `UnsafeMutablePointer<Int>` miscompiles at `-O` / `-Osize`.

## Why the false trails are valuable

Each false trail produced reusable artifacts:

- **Round 1 (`.Lifetimes` bisection)**: the 10-setting individual-feature sweep is a reusable template for bisecting any future swiftSettings-related compiler bug.
- **Round 2 (`unsafe` attribution)**: led to the realization that SwiftPM `swift test -c release` has different optimizer behavior than standalone `swiftc -O`. This is a calibration fact for future investigations — never trust SwiftPM-test-only behavior as a proxy for the bare compiler.
- **Round 3 (standalone extraction)**: produced the filing-ready 8-line reproducer that meets [ISSUE-002] gold standard.

## Methodology lessons (codified)

- `[ISSUE-005]` SIL Dump Analysis: should have happened earlier. The byte-identical SIL between with/without unsafe was the smoking gun that ruled out source-level attribution.
- `[ISSUE-013]` Variable Isolation: the SwiftPM 16-target sweep WAS variable isolation, but limited to `swiftSettings` and `unsafe`-keyword presence — both source-level. The actual trigger (chained `.advanced(by:)` with negative offset) was a SOURCE-PATTERN dimension that the SwiftPM sweep didn't vary.
- `[ISSUE-025]` In-Package Verification of Synthetic-Reproducer Claims: the cascade-claim discipline applies in reverse here — the SwiftPM test-target sweep made the bug LOOK narrower than it is. Standalone extraction broadened the trigger surface from "unsafe-bearing tests" to "any release-mode -O code with mixed-direction `.advanced(by:)`".

## Convergence outcome (2026-05-11, post-session)

An independent `/collaborative-discussion` between Claude and ChatGPT, run with
a minimal-context input pack (only the 8-line repro + execution recipe — no
investigation-arc context, no SIL findings, no Issues-repo reference),
converged on:

- **Toolchain defect confirmed** — not source-level UB. The source program is
  well-defined Swift; the chained `index_addr +M, −N` arithmetic stays within
  one live allocation on initialized element storage.
- **Mechanism isolated**: optimized SIL eliminates the live stores at array-literal
  intermediate indices (only stores at indices 0 and 4 of the 5-element literal
  survive). The chained `index_addr +4, −2` load reads from index 2, where
  no store survived → uninitialized memory. The Linux `-Osize` per-run variance
  is the unmistakable uninitialized-memory signature.
- **Trigger narrowed further** than this Investigation Arc had: requires
  `Array<T>` LITERAL initialization (not `Array(repeating:count:)`), trivial
  element type (not ARC-bearing class elements), chained compile-time-CONSTANT
  offsets (not parameterized), and storage through `_ContiguousArrayStorage` /
  CoW lowering (not manual `UnsafeMutableBufferPointer.allocate + initialize`
  nor `UnsafeMutablePointer<Int>.allocate(capacity:)`).
- **Known issue**: matches [`swiftlang/swift#77558`](https://github.com/swiftlang/swift/issues/77558)
  filed 2024-11-12 (title: "Code generation bug in release mode"). The Swift
  Forums thread "Code generation bug in release mode (Xcode 16.0)" of the same
  date is the user-facing surface.
- **Fixed on Swift 6.4-dev nightly-main** (commit `82b7720768ba875`).
  Candidate fix-commits per `git log --since=2024-11-12 -- lib/SILOptimizer/`:
  `1cbed39f326`, `de557cab56f`, `71381fab3c0`, `02fafc63d67` — all landed
  2025-10-10 with messages "Optimizer: support the new array literal
  initialization pattern in the {COWOpts | ArrayCountPropagation | ConstExpr |
  ForEachLoopUnroll} pass". COWOpts is the most directly suggestive given the
  converged trigger mentions CoW lowering.

### [ISSUE-001] keyword-search blind spot

Original keyword combinations searched in this investigation:
- "unsafe keyword pointer arithmetic", "advanced linux release miscompile",
  "unsafe expression SIL", "SE-0466 miscompile", "strictMemorySafety Linux",
  "SIL pointer load wrong", "swift -O linux miscompile", "release linux 6.3
  codegen", "unsafe pointee", "miscompile release linux".

None matched #77558 (titled "Code generation bug in release mode") because:
- The upstream report's title is generic ("Code generation bug in release mode")
- The upstream report's body framing emphasizes the Xcode build context, not the
  technical mechanism (array literal + chained offset + DSE)
- The 2024-11-12 Swift Forums thread of the same title is the user-facing
  framing — not searched by [ISSUE-001]

Recommended additional keywords for [ISSUE-001] future searches on this class:
- "miscompile array literal"
- "dead store elimination"
- "release mode pointer wrong value"
- "code generation bug release"
- "release mode array"
- Also: a Swift Forums search (not just GitHub Issues search). Many compiler
  bugs surface as Forums threads BEFORE the GitHub Issue is filed.

### De-escalation

Original scope: file a new swiftlang/swift issue with the 8-line repro + SIL
diff + trigger surface.

Revised scope: **comment on #77558** with the converged characterization
(deriving from the four-section template in
`/tmp/swift-pointer-bug-converged.md`). The comment carries the fresh standalone
repro, the opt-level matrix, the cross-platform table, the SIL evidence, and
the 6.4-dev-nightly-main fixes-it datapoint as confirming evidence of the
upstream report's root cause.

The investigation arc still had value despite landing on a known issue: it
produced a fresh standalone repro at filing-grade quality, empirically narrowed
trigger conditions (the SwiftPM 16-target sweep ruled out many candidates),
identified the fix-bearing nightly toolchain via cross-toolchain verification,
and surfaced the [ISSUE-001] keyword-search blind spot as actionable skill
feedback.

## Cross-References

- `swift-institute/Issues/swift-issue-pointer-arithmetic-linux-miscompile/ISSUE-77558-COMMENT.md` — comment text for [#77558](https://github.com/swiftlang/swift/issues/77558) (replaces the prior UPSTREAM-DRAFT.md)
- `swift-institute/Issues/swift-issue-pointer-arithmetic-linux-miscompile/README.md` — 16-target catalog (artifacts of false trails; institutional record)
- `swift-institute/Research/swift-compiler-bug-catalog.md` — entry in "Fixed upstream on 6.4-dev nightly-main"
- `swift-affine-primitives/Tests/Affine Primitives Tests/AffineSLITests.swift::unsafeMutablePointerMinusTypedOffset` — in-tree fix detector (gated off via `.disabled(if: isLinux)` + `.bug(URL, ...)`)
- Skill: `[ISSUE-001]`, `[ISSUE-005]`, `[ISSUE-013]`, `[ISSUE-025]`, `[ISSUE-026]`
- Skill: `[ISSUE-028]` — compiler bug catalog consultation
- `/tmp/swift-pointer-bug-converged.md` — converged plan from independent `/collaborative-discussion` (Claude + ChatGPT, 2026-05-11)
