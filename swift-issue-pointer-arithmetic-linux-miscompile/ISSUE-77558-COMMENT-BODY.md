Possibly the same root cause as this issue, surfaced via chained `advanced(by:)` on Array storage. **Fires under `swift test -c release` on `swiftlang/swift:6.3.1-RELEASE` Linux Docker; does not reproduce under standalone `swiftc -O` on the same Docker image or on current Apple Swift 6.3.1 / Xcode 26.** Does **not** reproduce on `swiftlang/swift:nightly-main`, so the defect appears toolchain-side and fixed on main.

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

### Trigger surface narrowing — empirically verified 2026-05-11

The bug-firing surface on current toolchain images is **gated by the SwiftPM-test-runner build path**, not by bare `swiftc -O` on the minimum reproducer:

| Path | Toolchain | Result |
|---|---|---|
| `swift test -c release --filter <target>` | `swiftlang/swift:6.3.1-RELEASE` Linux x86_64 (and aarch64) Docker | **FIRES** — `backed.pointee` reads a value other than the initialized `20`; Swift Testing records the misload via `withKnownIssue` (Expectation failed: backed.pointee == 20). Load-bearing CI signal. |
| `swiftc -O minimum-repro.swift -o /tmp/r && /tmp/r` | `swiftlang/swift:6.3.1-RELEASE` Linux x86_64 (and aarch64) Docker | does not fire (exit 0, reads 20) |
| `swiftc -O minimum-repro.swift -o /tmp/r && /tmp/r` | Apple Swift 6.3.1 (swiftlang-6.3.1.1.2) / Xcode 26 / macOS 26 / arm64 | does not fire (exit 0, reads 20) — see caveat below |
| `swift test -c release` | `swiftlang/swift:nightly-main-jammy` (Swift 6.4-dev) | **Expectation-not-recorded** — `withKnownIssue` flip; suite reports the expected-fail-was-not-met; fix landed |

Multiple repro shapes probed for the standalone `swiftc -O` rows (operator-wrapped, direct `.advanced(by:)` without operator wrappers, function-wrapped, byte-for-byte mirror of the test body); all return 20 / exit 0 on current toolchain images.

**Hypothesis**: SwiftPM's test target build flags include a combination (`-enable-testing`, `-package-name`, specific module-build flags, etc.) that exposes the optimizer bug when compiling the test target's source, while pure `swiftc -O` on the same source omits the relevant flag combination. Standalone-vs-SwiftPM-test divergence on the same source is unusual and may help narrow which optimizer pass owns the issue.

### Trigger characterization (variant probes, performed via the SwiftPM-test-runner path)

Confirmed by variant probes:
- ✓ Bugs with array literal of trivial type (`Int`, POD `struct P { let a: Int }`)
- ✓ Does NOT bug with `Array(repeating:count:)` + sequential subscript writes
- ✓ Does NOT bug with class element type (ARC-bearing payload blocks the transformation)
- ✓ Does NOT bug with manual `UnsafeMutableBufferPointer.allocate + initialize`
- ✓ Does NOT bug with hand-rolled `UnsafeMutablePointer<Int>.allocate(capacity:)`
- ✓ Does NOT bug when `m` and `n` come in as function parameters
- ✓ Does NOT bug when the chain is collapsed to a single positive `advanced(by:)`
- ✓ Does NOT bug when a side-effect read of every element precedes the chain

### Optimized SIL symptom

The literal `[0, 10, 20, 30, 40]` produces only **two** stores in optimized SIL — at offsets 0 and 4 of the five-element tail-allocated `_ContiguousArrayStorage<Int>`:

```
%3 = ref_tail_addr %2, $Int
store %5 to %3                                 // values[0] = 0
%8 = index_addr %3, %7                         // %7 = Word 4
store %10 to %8                                // values[4] = 40
... (begin/end_cow_mutation) ...
%18 = ref_tail_addr %17, $Int
%19 = index_addr [stack_protection] %18, %7    // base + 4
%20 = integer_literal $Builtin.Word, -2
%21 = index_addr [stack_protection] %19, %20   // (base + 4) + (-2) = base + 2
%22 = load %21
```

Stores for indices 1, 2, 3 (values 10, 20, 30) were eliminated as dead. The chained `index_addr +4, -2` load reads from `base + 2`, where no store survived. The earlier-toolchain Linux `-Osize` per-run output variance (e.g., `281473255028284 → 281473464743484`; observed during initial convergence on toolchains we don't retain — not reproducible on current `swift:6.3.1-RELEASE` Docker, see Caveats below) is the unmistakable signature of an uninitialized-memory read: the binary is deterministic, but the loaded slot's prior contents change per run.

### Caveats on prior observations

An earlier internal convergence run captured macOS arm64 standalone `swiftc -O` producing `8587494688` (garbage) and `swiftc -Osize` producing `8588599072`, and Linux x86_64 standalone producing `1` deterministic / per-run variance under `-Osize`. **Re-probing on 2026-05-11 does not reproduce these standalone observations** on either:

- Apple Swift 6.3.1 (`swiftlang-6.3.1.1.2`) on macOS 26 / Xcode 26 / arm64 — likely because Apple's 6.3.x distribution carries the 2025-10-10 upstream fix-quad backport.
- `swiftlang/swift:6.3.1-RELEASE` Docker on Linux x86_64 (emulated) and aarch64 — toolchain reports `Swift version 6.3.1 (swift-6.3.1-RELEASE)` and exits 0 on the minimum standalone repro at every optimization level.

The Linux `-O` test-runner path still fires the bug (verified through `swift test -c release` against the same Docker image), so the issue is not fixed on the upstream `swift:6.3.1-RELEASE` distribution — the firing surface has just narrowed to the SwiftPM-test build path on the current minimum repro.

### Fix status

Does NOT reproduce on:

- `swiftlang/swift:nightly-main`, identifying as `Swift version 6.4-dev (LLVM d2079213f1d4451, Swift 82b7720768ba875)`, target `aarch64-unknown-linux-gnu`.

Reproduces on (SwiftPM-test-runner path only on current 6.3.1):

- `swift:6.3.1-RELEASE` Docker image (`x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu`)

Candidate fix commits per `git log --since=2024-11-12 -- lib/SILOptimizer/` (all 2025-10-10, "Optimizer: support the new array literal initialization pattern in the ... pass"):

- [`1cbed39f326`](https://github.com/swiftlang/swift/commit/1cbed39f326) — COWOpts pass (directly matches the converged CoW-lowering trigger)
- [`de557cab56f`](https://github.com/swiftlang/swift/commit/de557cab56f) — ArrayCountPropagation pass
- [`71381fab3c0`](https://github.com/swiftlang/swift/commit/71381fab3c0) — ConstExpr
- [`02fafc63d67`](https://github.com/swiftlang/swift/commit/02fafc63d67) — ForEachLoopUnroll pass

### Workaround

The same workaround pattern reported in this issue restores correct behavior on the affected toolchains: insert an opaque side effect that observes every element before the chained-`advanced(by:)` load, e.g., `for v in values { _ = v }` (or any equivalent forcing pass that prevents the DSE of the live-element stores).

### Continuous fix-detection

This issue carries an in-tree `withKnownIssue`-based fix-detection harness at [swift-institute/Issues/swift-issue-pointer-arithmetic-linux-miscompile](https://github.com/swift-institute/Issues/tree/main/swift-issue-pointer-arithmetic-linux-miscompile). The per-issue CI matrix runs `swift test -c release` against `swiftlang/swift:nightly-main-jammy` on a weekly cron; when the `withKnownIssue` block stops firing on nightly (i.e., the fix has propagated to a distribution we consume), that leg flips red and surfaces the close signal automatically.
