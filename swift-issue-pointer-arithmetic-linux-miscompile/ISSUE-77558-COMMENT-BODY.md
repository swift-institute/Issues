Possibly the same root cause as this issue, surfaced via chained `advanced(by:)` on Array literal storage. **Fires under `swift test -c release` on `swift:6.3-jammy` Linux Docker; does not reproduce under standalone `swiftc -O` on the same Docker image or on current Apple Swift 6.3.1 / Xcode 26.** Does **not** reproduce on `swiftlang/swift:nightly-main-jammy`, so the defect appears toolchain-side and fixed on main.

### Minimal repro

```swift
public func bug() -> Int {
    var values: [Int] = [0, 10, 20, 30, 40]
    return values.withUnsafeMutableBufferPointer { buf in
        let base = buf.baseAddress!.advanced(by: 4)
        let backed = base.advanced(by: -2)
        return backed.pointee
    }
}
print(bug())
```

This is the structural reduction. **It does not fire under bare `swiftc -O` on current 6.3.x distributions** — only via the SwiftPM-test-runner path (see "Trigger surface narrowing" below). The in-tree test harness at [`Tests/Reproducer.swift`](https://github.com/swift-institute/Issues/blob/main/swift-issue-pointer-arithmetic-linux-miscompile/Tests/Reproducer.swift) uses an operator-wrapped variant of the same chained-`.advanced(by:)` pattern (`base + Vec(4)`, `advanced - Vec(2)` over user-authored `+`/`-` overloads); that's the form actually exercised by the CI matrix. Compile in Swift 5 or Swift 6 language modes without strict memory safety; add `unsafe` markers per SE-0466 if compiling under `.strictMemorySafety()`.

### Trigger surface narrowing — empirically verified 2026-05-11

The bug-firing surface on current toolchain images is **gated by the SwiftPM-test-runner build path**, not by bare `swiftc -O` on the minimum reproducer:

| Path | Toolchain | Result |
|---|---|---|
| `swift test -c release --filter <target>` | `swift:6.3-jammy` Docker — Linux x86_64 (and aarch64) | **FIRES** — `backed.pointee` reads a value other than the initialized `20`; Swift Testing records the misload via `withKnownIssue` (Expectation failed: backed.pointee == 20). Load-bearing CI signal. |
| `swiftc -O minimum-repro.swift -o /tmp/r && /tmp/r` | `swift:6.3-jammy` Docker — Linux x86_64 (and aarch64) | does not fire (exit 0, reads 20) |
| `swiftc -O minimum-repro.swift -o /tmp/r && /tmp/r` | Apple Swift 6.3.1 (swiftlang-6.3.1.1.2) / Xcode 26 / macOS 26 / arm64 | does not fire (exit 0, reads 20) — see caveat below |
| `swift test -c release` | `swiftlang/swift:nightly-main-jammy` (Swift 6.4-dev) | **Expectation-not-recorded** — `withKnownIssue` flip; suite reports the expected-fail-was-not-met; fix landed |

Multiple standalone repro shapes probed (operator-wrapped, direct `.advanced(by:)` without operator wrappers, function-wrapped, byte-for-byte mirror of the test body); all return 20 / exit 0 on current toolchain images.

**Hypothesis**: SwiftPM's test target build flags include a combination (`-enable-testing`, `-package-name`, specific module-build flags, etc.) that exposes the optimizer bug when compiling the test target's source, while pure `swiftc -O` on the same source omits the relevant flag combination. Standalone-vs-SwiftPM-test divergence on the same source is unusual and may help narrow which optimizer pass owns the issue.

### Trigger characterization

Empirically isolated in the in-tree investigation arc ([INVESTIGATION-ARC.md §Round 3](https://github.com/swift-institute/Issues/blob/main/swift-issue-pointer-arithmetic-linux-miscompile/INVESTIGATION-ARC.md)):

- ✗ Single `.advanced(by:)` step: does NOT fire
- ✗ Subscript `buf[2]` (no `.advanced`): does NOT fire
- ✗ Two chained `.advanced(by:)` calls, both positive: does NOT fire
- ✓ Two chained `.advanced(by:)` calls, at least one negative: FIRES

Additional variant hypotheses from independent model-to-model convergence (not individually re-verified on the current toolchain; offered as candidate narrowing for maintainer-side validation):

- Trigger appears specific to array literals of trivial element type; does NOT appear under `Array(repeating:count:)` + sequential subscript writes
- Does NOT appear under class element type (ARC-bearing payload blocks the transformation)
- Does NOT appear with manual `UnsafeMutableBufferPointer.allocate + initialize`
- Does NOT appear with hand-rolled `UnsafeMutablePointer<Int>.allocate(capacity:)`
- Does NOT appear when offsets come in as function parameters
- Does NOT appear when a side-effect read of every element precedes the chain

### Optimized SIL pattern

Real `swiftc -O -emit-sil` on `swift:6.3-jammy` confirms the structural pattern: the array-literal initialization produces a `ref_tail_addr` on `_ContiguousArrayStorage<Int>` followed by chained `index_addr` instructions. The chained offsets in the reproducer fold to `base + 4` then `+ (-2) = base + 2`:

```
%base = ref_tail_addr %storage, $Int
%offset_4   = integer_literal $Builtin.Word, 4
%advanced   = index_addr [stack_protection] %base, %offset_4
%offset_n2  = integer_literal $Builtin.Word, -2
%backed     = index_addr [stack_protection] %advanced, %offset_n2
%loaded     = load %backed
```

If dead-store elimination drops the array literal's intermediate-index stores (only the boundary stores at offsets 0 and 4 surviving), the chained `index_addr +4, -2` load lands on offset 2, where no surviving store reaches — uninitialized memory. The earlier-toolchain Linux `-Osize` per-run output variance, observed during initial convergence but not reproducible on current `swift:6.3-jammy` Docker (see Caveats), is the signature of exactly that uninitialized-memory read.

(SIL value numbers are not quoted verbatim because they vary by toolchain/configuration; the structural pattern above is reproducible at any `-emit-sil` site on a firing build.)

### Caveats on prior observations

An earlier internal convergence run captured macOS arm64 standalone `swiftc -O` producing `8587494688` (garbage) and `swiftc -Osize` producing `8588599072`, and Linux x86_64 standalone producing deterministic-`1` and per-run output variance under `-Osize`. **Re-probing on 2026-05-11 does not reproduce these standalone observations** on either:

- Apple Swift 6.3.1 (`swiftlang-6.3.1.1.2`) on macOS 26 / Xcode 26 / arm64 — likely because Apple's 6.3.x distribution carries the 2025-10-10 upstream fix-quad backport.
- `swift:6.3-jammy` Docker on Linux x86_64 (emulated) and aarch64 — toolchain reports `Swift version 6.3.1 (swift-6.3.1-RELEASE)` and exits 0 on the minimum standalone repro at every optimization level.

The Linux `-O` test-runner path still fires the bug (verified through `swift test -c release` against the same Docker image), so the issue is not fixed on the upstream `swift:6.3-jammy` distribution — the firing surface has just narrowed to the SwiftPM-test build path on the current minimum repro.

### Fix status

Does NOT reproduce on:

- `swiftlang/swift:nightly-main-jammy`, identifying as `Swift version 6.4-dev (LLVM d2079213f1d4451, Swift 82b7720768ba875)`, target `aarch64-unknown-linux-gnu` (and x86_64 via emulation).

Reproduces on (SwiftPM-test-runner path only on current 6.3.1):

- `swift:6.3-jammy` Docker image (`x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu`)

Candidate fix commits per `git log --since=2024-11-12 -- lib/SILOptimizer/` (all 2025-10-10):

- [`1cbed39f326`](https://github.com/swiftlang/swift/commit/1cbed39f326) — Optimizer: support the new array literal initialization pattern in the COWOpts pass (directly matches the converged CoW-lowering trigger)
- [`de557cab56f`](https://github.com/swiftlang/swift/commit/de557cab56f) — Optimizer: support the new array literal initialization pattern in the ArrayCountPropagation pass
- [`71381fab3c0`](https://github.com/swiftlang/swift/commit/71381fab3c0) — ConstExpr: support the new array literal initialization pattern
- [`02fafc63d67`](https://github.com/swiftlang/swift/commit/02fafc63d67) — Optimizer: support the new array literal initialization pattern in the ForEachLoopUnroll pass

### Workaround

The same workaround pattern reported in this issue restores correct behavior on the affected toolchains: insert an opaque side effect that observes every element before the chained-`advanced(by:)` load, e.g., `for v in values { _ = v }` (or any equivalent forcing pass that prevents the DSE of the live-element stores).

### Continuous fix-detection

This issue carries an in-tree `withKnownIssue`-based fix-detection harness at [swift-institute/Issues/swift-issue-pointer-arithmetic-linux-miscompile](https://github.com/swift-institute/Issues/tree/main/swift-issue-pointer-arithmetic-linux-miscompile). The per-issue CI matrix runs `swift test -c release` against `swiftlang/swift:nightly-main-jammy` on a weekly cron; when the `withKnownIssue` block stops firing on nightly (i.e., the fix has propagated to a distribution we consume), that leg flips red and surfaces the close signal automatically.
