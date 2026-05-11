# ISSUE-77558-COMMENT — `gh issue comment` text for swiftlang/swift#77558 (NOT YET SUBMITTED)

**Status**: drafted per the converged template from
`/tmp/swift-pointer-bug-converged.md` (independent `/collaborative-discussion`
between Claude and ChatGPT, 2026-05-11). Awaiting explicit user authorization
before `gh issue comment 77558 -R swiftlang/swift`.

**Context**: Originally drafted as new-issue body (`UPSTREAM-DRAFT.md`);
retired and replaced with this comment-on-existing-issue draft after the
convergence identified [`swiftlang/swift#77558`](https://github.com/swiftlang/swift/issues/77558)
(filed 2024-11-12, title: "Code generation bug in release mode") as the
matching upstream report.

---

## Comment body (paste into `gh issue comment 77558 -R swiftlang/swift --body-file <this file's body section below>`)

Possibly the same root cause as this issue, surfaced via chained `advanced(by:)` on Array storage. Reproduced on `swift:6.3` (Linux x86_64) and Apple Swift 6.3.1 (macOS arm64); does **not** reproduce on `swiftlang/swift:nightly-main` (Swift 6.4-dev / aarch64-linux), so the defect appears toolchain-side and already fixed on main.

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

### Expected vs observed

| Configuration | Output |
|---|---|
| macOS arm64, Swift 6.3.1, `-Onone` | 20 |
| macOS arm64, Swift 6.3.1, `-O` | 8587494688 |
| macOS arm64, Swift 6.3.1, `-Osize` | 8588599072 |
| Linux x86_64, swift:6.3, `-Onone` | 20 |
| Linux x86_64, swift:6.3, `-O` | 1 (deterministic) |
| Linux x86_64, swift:6.3, `-Osize` | varies per run (e.g. 281473255028284 → 281473464743484) |
| Linux aarch64, nightly-main 6.4-dev, any opt | 20 |

The Linux `-Osize` per-run variance is the unmistakable signature of an uninitialized-memory read: the binary is deterministic, but the loaded slot's prior contents change.

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

Stores for indices 1, 2, 3 (values 10, 20, 30) were eliminated as dead. The chained `index_addr +4, -2` load reads from `base + 2`, where no store survived.

### Trigger characterization

Confirmed by variant probes (all on macOS -O):
- ✓ Bugs with array literal of trivial type (`Int`, POD `struct P { let a: Int }`)
- ✓ Does NOT bug with `Array(repeating:count:)` + sequential subscript writes
- ✓ Does NOT bug with class element type (ARC-bearing payload blocks the transformation)
- ✓ Does NOT bug with manual `UnsafeMutableBufferPointer.allocate + initialize`
- ✓ Does NOT bug with hand-rolled `UnsafeMutablePointer<Int>.allocate(capacity:)`
- ✓ Does NOT bug when `m` and `n` come in as function parameters
- ✓ Does NOT bug when the chain is collapsed to a single positive `advanced(by:)`
- ✓ Does NOT bug when a side-effect read of every element precedes the chain

### Fix status

Reproduces on:
- Apple Swift 6.3.1 (`swift-driver 1.148.6 / arm64-apple-macosx26.0`)
- `swift:6.3` Docker image (`x86_64-unknown-linux-gnu`)

Does NOT reproduce on:
- `swiftlang/swift:nightly-main`, identifying as `Swift version 6.4-dev (LLVM d2079213f1d4451, Swift 82b7720768ba875)`, target `aarch64-unknown-linux-gnu`.

Candidate fix commits per `git log --since=2024-11-12 -- lib/SILOptimizer/` (all 2025-10-10, "Optimizer: support the new array literal initialization pattern in the ... pass"):

- [`1cbed39f326`](https://github.com/swiftlang/swift/commit/1cbed39f326) — COWOpts pass (directly matches the converged CoW-lowering trigger)
- [`de557cab56f`](https://github.com/swiftlang/swift/commit/de557cab56f) — ArrayCountPropagation pass
- [`71381fab3c0`](https://github.com/swiftlang/swift/commit/71381fab3c0) — ConstExpr
- [`02fafc63d67`](https://github.com/swiftlang/swift/commit/02fafc63d67) — ForEachLoopUnroll pass

The same workaround pattern reported in this issue (inserting an opaque side effect — here a `for v in values { observe(v) }` loop) restores correct behavior on the affected toolchains.

---

## Filing checklist

- [ ] User authorizes `gh issue comment 77558 -R swiftlang/swift` with the body above
- [ ] After commenting: post URL back to this file and to `swift-affine-primitives/Tests/.../AffineSLITests.swift` `.bug(URL, ...)` trait
- [ ] Update `swift-institute/Research/swift-compiler-bug-catalog.md` "Fixed upstream on 6.4-dev nightly-main" entry to cross-link the comment

## See also

- `/tmp/swift-pointer-bug-converged.md` — converged plan
- `/tmp/swift-pointer-bug-round-1-for-chatgpt.md` — input pack
- `/tmp/swift-pointer-bug-round-2-claude.md` — Round 2 transcript
- `swift-institute/Issues/swift-issue-pointer-arithmetic-linux-miscompile/INVESTIGATION-ARC.md` — full arc + blind-spot analysis
