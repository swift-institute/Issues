# Evidence — investigation artifacts

Sixteen `.swift` files preserved from the bisection arc that landed on
[`swiftlang/swift#77558`](https://github.com/swiftlang/swift/issues/77558).

These were SwiftPM test targets during the investigation; they are now
plain source files. The Tests/ + Sources/Reproducer/ pair at the
per-issue directory root carries the converged minimum reproducer +
exit-code probe. This directory carries the convergence audit trail.

Read [`../INVESTIGATION-ARC.md`](../INVESTIGATION-ARC.md) for the
chronological account — three sequential false hypotheses (`.Lifetimes`
trigger → `unsafe`-keyword trigger → actual: chained `.advanced(by:)`
with mixed-direction offsets at `-O`) and the disambiguator targets
each one demanded.

## File index

| File | Role in the arc |
|---|---|
| `Control.swift` | No swiftSettings, `unsafe` markers present — the baseline that exposed the `.Lifetimes` hypothesis as false (when the Control failed too). |
| `WithLifetimes.swift` | First-hypothesized unique trigger (`.enableExperimentalFeature("Lifetimes")`). Refuted by Control. |
| `WithStrictMemorySafety.swift`, `WithExistentialAny.swift`, `WithInternalImportsByDefault.swift`, `WithMemberImportVisibility.swift`, `WithNonisolatedNonsendingByDefault.swift`, `WithLifetimeDependenceExperimental.swift`, `WithSuppressedAssociatedTypes.swift`, `WithInferIsolatedConformances.swift`, `WithLifetimeDependenceUpcoming.swift` | The other 9 swiftSettings from `swift-affine-primitives`, each in isolation. All failed on Linux release; uniqueness disproof for every individual feature. |
| `WithoutUnsafe.swift` | Identical source minus `unsafe` keyword markers. Passed on Linux release — appeared to nominate `unsafe` as the trigger (Round 2). |
| `WithUnsafeInOperatorBodyOnly.swift`, `WithUnsafeAtCallSiteOnly.swift` | Body-only vs call-site-only `unsafe` placement experiments — pin down which `unsafe` position is load-bearing. |
| `WithoutOperator.swift`, `WithoutOperatorAndWithoutUnsafe.swift` | Drop the user-authored `+`/`-` operators entirely; call `.advanced(by:)` directly. Tests whether the bug needs operator wrappers (it doesn't — see Round 3). |

## Why preserved

Per [META-016] in `swift-institute/Skills/corpus-meta-analysis/`:
empirically-derived institutional knowledge survives in the corpus even
when superseded — convergence threads need to be reconstructible to
justify the upstream filing's reduced shape. Deleting the bisection
variants would erase the audit trail that the converged 8-line repro
relies on for credibility.

## Discrepancy: standalone `swiftc -O` does not fire on current 6.3.1 toolchains

The convergence discussion captured in `INVESTIGATION-ARC.md` §"Round 3"
recorded the bug firing on macOS arm64 standalone `swiftc -O` ("output
8587494688 (garbage)") and on Linux x86_64 standalone `swiftc -O`. Re-probing
on 2026-05-11 against the current toolchain images yields exit 0 (no bug)
across the board:

| Toolchain | Triple | Standalone `swiftc -O` result |
|---|---|---|
| Apple Swift 6.3.1 (swiftlang-6.3.1.1.2) | `arm64-apple-macosx26.0` | exit 0 (`-O`, `-Osize`, `-Onone` all return 20) |
| `swift:6.3-jammy` Docker, native | `aarch64-unknown-linux-gnu` | exit 0 |
| `swift:6.3-jammy` Docker, x86_64 (emulated) | `x86_64-unknown-linux-gnu` | exit 0 |

Variants probed (each returning 20, exit 0):
- The canonical operator-wrapped source (this repo's `Sources/Reproducer/main.swift`).
- Direct `base.advanced(by: 4).advanced(by: -2)` chains without operator wrappers.
- Function-wrapped repro returning the value from a non-top-level scope.
- Byte-for-byte mirror of the test body (`@Test` minus the `withKnownIssue` wrapper), reading `backed.pointee` inside the closure via side-effect.

**The bug does still fire via `swift test -c release` on Linux release**
in the same `swift:6.3-jammy` container — confirmed 2026-05-11 by running
`swift test -c release --filter swift_issue_pointer_arithmetic_linux_miscompile`
and observing `Test reproducer() recorded a known issue at Reproducer.swift:62:21: Expectation failed: unsafe backed.pointee == 20` (i.e., `withKnownIssue` caught the firing bug exactly as designed).

Two hypotheses are consistent with this data:

1. **Apple-side backport for macOS**: Apple's 6.3.x distribution carries the
   upstream fix-quad (`swiftlang/swift` commits `1cbed39f326` / `de557cab56f`
   / `71381fab3c0` / `02fafc63d67`, landed 2025-10-10). This would explain
   the macOS-arm64 row but not the Linux rows on the same `swift:6.3-jammy`
   image that still fires the bug via `swift test`.
2. **SwiftPM-test-runner-gated firing**: per INVESTIGATION-ARC.md §Round 2,
   "the `unsafe` attribution was an artifact of SwiftPM test-framework build
   flags happening to gate which configurations expose the optimizer bug."
   The pure `swiftc -O` invocation on the minimum reproducer omits whatever
   flag combination SwiftPM's test target build uses; the bug fires only via
   the SwiftPM-test path. The convergence's "standalone fires" claim may
   have been against a different repro shape (e.g., the larger
   `swift-affine-primitives` test-target call shape) where the relevant
   flags were present.

Hypothesis (2) is the more conservative reading — it requires no
toolchain-distribution divergence to explain the data. The empirical
narrowing of the bug's firing surface (SwiftPM test path only, not
bare `swiftc -O`) is itself research-worthy data for the upstream
`#77558` comment.

**Practical CI consequence**: the per-issue CI matrix relies on
`swift test -c release` through the canonical swift-institute reusable's
`linux-release` leg. That path fires the bug and `withKnownIssue` catches
it. The standalone executable target (`swift-issue-pointer-arithmetic-linux-miscompile-Repro`)
remains in the package as a local-probing tool for ad-hoc toolchain
investigation, but it is no longer a reliable CI signal on current toolchain
images and is not gated in CI.

Practical consequence for this repo's CI shape:

- macOS test legs through the `swift-institute` reusable run
  `swift test -c debug --filter swift_issue_pointer_arithmetic_linux_miscompile`.
  `withKnownIssue`'s `when: { isLinuxRelease() }` precondition is
  false on macOS, so the wrapped block runs unguarded and passes
  naturally regardless of whether the bug fires.
- Linux release test legs (`swift:6.3` container) fire the bug;
  `withKnownIssue` catches it; suite passes.
- Linux nightly test legs (`swiftlang/swift:nightly-main-jammy`,
  fix landed) run the wrapped block without firing the issue;
  Swift Testing reports the expected failure as unmet → red flip
  → upstream-fix-detection signal.

The macOS standalone executable (`Sources/Reproducer/main.swift`) is
retained as a local-validation tool rather than a CI gate. It is the
canonical 8-line repro shape; running it on a candidate older Apple
toolchain or a Linux Docker container is the fastest way to verify
whether a given toolchain carries the fix without standing up the
full Swift Testing matrix.
