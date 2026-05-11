# UPSTREAM-DRAFT — swiftlang/swift issue body (NOT YET SUBMITTED)

**Status**: drafted per [ISSUE-017] format; awaiting explicit user authorization
before `gh issue create swiftlang/swift`.

---

## Title

Miscompile: chained `UnsafeMutablePointer.advanced(by:)` with mixed-direction offsets returns wrong value under `-O` / `-Osize` (macOS + Linux)

## Body

### Classification

**Miscompile** — code compiles cleanly; the produced binary reads from the wrong memory address.

### Environment

| | |
|---|---|
| Swift versions | 6.3.1 release (`swift-6.3.1-RELEASE`) and 6.4-dev nightly |
| Platforms affected | macOS arm64 (aarch64-apple-macosx14.0), Linux x86_64 + aarch64 (`swift:6.3` Docker container) |
| Optimization levels affected | `-O`, `-Osize` |
| Optimization levels unaffected | `-Onone` |
| Module mode | Single-file `swiftc` (no SwiftPM, no WMO required) |

### Reproducer

8 lines of Swift, no dependencies, builds with bare `swiftc`:

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

**Command**: `swiftc -O bug.swift -o bug && ./bug`

**Observed (macOS arm64 -O)**: `8587494688` (garbage; pointer-shaped value)
**Observed (Linux x86_64 -O)**: `1`
**Observed (any platform -Osize)**: garbage value (differs across platforms)
**Expected**: `20` (the value at `values[2]`)
**Observed (any platform -Onone)**: `20` (correct)

### Optimization-level discrimination

Same source, same toolchain, three optimization levels:

| Optimization | macOS arm64 output | Linux x86_64 output |
|---|---|---|
| `-O` | `8587494688` (garbage) | `1` |
| `-Osize` | garbage (differs from `-O`) | `281473580086844` (garbage) |
| `-Onone` | `20` (correct) | `20` (correct) |

`-O` and `-Osize` produce DIFFERENT wrong values — suggests two distinct buggy codegen paths in the optimizer.

### SIL / LLVM IR evidence (bug is below SIL level)

The same reproducer with the `unsafe` keyword expression (`SE-0466`) on the
`.advanced(by:)` calls produces **byte-identical SIL** and **byte-identical
LLVM IR** as the form without `unsafe`. The only diff is the source-filename
comment in the file header. This holds on both macOS (`xcrun swiftc -O -emit-sil`)
and Linux (`swiftc -O -emit-sil` in `swift:6.3` container).

This implies:
- The `unsafe` annotation is correctly NOT semantic at SIL level.
- The miscompile is in a later pipeline stage — LLVM optimization or backend codegen.
- The trigger is the Swift source pattern, not the optimization mode disambiguation that some configurations expose.

### Trigger surface

The bug requires a specific Swift source pattern. Variants tested in isolation:

| Pattern | -O result |
|---|---|
| `buf.baseAddress!.advanced(by: 2).pointee` (single step) | passes |
| `buf[2]` (subscript) | passes |
| `let a = base.advanced(by: 1); let b = a.advanced(by: 1); b.pointee` (both positive) | passes |
| `let a = base.advanced(by: 4); let b = a.advanced(by: -2); b.pointee` (mixed direction) | **FAILS** |
| `base.advanced(by: 4).advanced(by: -2).pointee` (chained, mixed) | **FAILS** |
| `let a = base.advanced(by: 3); let b = a.advanced(by: -1); b.pointee` (different offsets, mixed) | **FAILS** |
| `let a = base.advanced(by: 4); let b = a.advanced(by: -1).advanced(by: -1); b.pointee` (three-step mixed) | **FAILS** |

**The miscompile requires**: at least two `.advanced(by:)` calls in a chain on `UnsafeMutablePointer<Int>` where at least one offset is negative. Single advances, subscript access, and all-positive multi-step advances all produce correct output.

`Int` is the only `Pointee` exhaustively tested; other types not yet checked.

### Workarounds tried that did NOT help

Each was applied symmetrically across user-authored `+` / `-` operator overloads that wrap `.advanced(by:)`:

| Attempt | Result |
|---|---|
| Explicit local `let offset = Int(bitPattern: rhs)` before `-offset` | still fails |
| Swap `@_transparent` → `@inlinable` on the operator | still fails |
| Wrap arithmetic in `withExtendedLifetime(rhs) { ... }` | still fails |
| Add `unsafe` keyword (SE-0466) at call sites | still fails |
| Remove `unsafe` keyword at call sites | still fails standalone; some SwiftPM test-target shapes pass — likely because the test framework's build flags limit optimizer reach |

The user-level fixes all fail because the miscompile is in the optimizer's handling of the pattern, not in the operator body or the source-level annotation.

### Heisenbug character

Any source-level instrumentation between the second `.advanced(by:)` call and the `.pointee` read structurally masks the bug:

- A `print()` of the intermediate pointer (`print(UInt(bitPattern: backed))`) heals the test.
- An intermediate `let _ = UInt(bitPattern: backed)` materialization heals the test.
- A reference to `backed` in a `#expect` failure-message string interpolation heals the test.

The reproducer above is the minimum that consistently fires the bug across `-O` and `-Osize` on both platforms.

### Suggested investigation

- SIL identical between affected and unaffected source patterns → the trigger lives in LLVM optimization or backend codegen, not in SIL.
- The Heisenbug pattern (any read of the result pointer masks the miscompile) suggests an aliasing-analysis or dead-store-elimination issue around the `GEP` for negative-offset pointer arithmetic.
- Pass bisection per [ISSUE-011] not yet performed; suggested as a next step for the maintainers familiar with the LLVM Swift backend.

### Side-by-side demonstration

See `swift-institute/Issues` for a 16-target SwiftPM catalog of the investigation, including the failed bisection trails (the `unsafe`-keyword attribution that turned out to be an artifact of SwiftPM test-framework build-flag gating, not a real semantic trigger).

The 8-line reproducer in this issue body is the consolidated minimum.

---

## Suggested Labels

`bug`, `miscompile`, `optimization`, `codegen`, `unsafe-pointer`, `release-mode`,
`linux`, `macos`

## Filing checklist

- [ ] User authorizes `gh issue create`
- [ ] After filing: post URL back to this DRAFT file
- [ ] After filing: update `swift-institute/Research/swift-compiler-bug-catalog.md` with the issue link
- [ ] After filing: update `swift-affine-primitives/Tests/.../AffineSLITests.swift` `.bug(URL, ...)` trait to point at the swiftlang/swift issue
