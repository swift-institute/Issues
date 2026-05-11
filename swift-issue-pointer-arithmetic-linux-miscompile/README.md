# Swift Issue: Linux Release-Mode Pointer Arithmetic Miscompile

**Bug Report:** Pending — issue body drafted, awaiting filing at swiftlang/swift.

Minimal reproducer for a Linux-only release-mode codegen miscompile in which a
`.pointee` read after a user-authored pointer arithmetic operator returns the
value at the wrong address.

## Bug Summary

User-authored `+` / `-` operator overloads on `UnsafeMutablePointer<Int>` that
wrap `.advanced(by:)` produce correct pointer values, but the subsequent
`.pointee` load reads from the wrong address. Affects only Linux release builds
on Swift 6.3 stable and 6.4-dev nightly; macOS, Windows, and Linux debug all
pass.

The arithmetic itself is correct — printing `UInt(bitPattern:)` of the
intermediate pointers between the operator call and the load yields the
expected addresses. The miscompile is at the load codegen, not the operator
body.

## Reproduction

```bash
# On Linux with Swift 6.3 or 6.4-dev nightly:
git clone https://github.com/swift-institute/Issues.git
cd Issues
swift test -c release --filter PointerArithmeticReduced
```

The test `reducedRepro` fails on Linux release. On macOS, Windows, and Linux
debug, it passes. The targets `PointerArithmeticLinuxMiscompile` and
`PointerArithmeticLinuxMiscompileTests` are registered in the top-level
`Package.swift` and point into this sub-directory's `Sources/` and `Tests/`.

## Environment

- **Swift versions:** 6.3 stable, 6.4-dev nightly
- **Platform:** Linux (Ubuntu jammy, swift:6.3 and swiftlang/swift:nightly-main-jammy containers)
- **Works on:** macOS (any build), Linux debug, Windows

## Minimal Code

**Sources/PointerArithmetic/PointerArithmetic.swift:**

```swift
public struct Vec {
    public let raw: Int
    public init(_ r: Int) { self.raw = r }
}

public func + (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    lhs.advanced(by: rhs.raw)
}

public func - (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    lhs.advanced(by: -rhs.raw)
}
```

**Tests/PointerArithmeticTests/PointerArithmeticTests.swift:**

```swift
@Test
func reducedRepro() {
    var values: [Int] = [0, 10, 20, 30, 40]
    values.withUnsafeMutableBufferPointer { buf in
        let base = buf.baseAddress!
        let advanced = base + Vec(4)
        let backed = advanced - Vec(2)
        #expect(backed.pointee == 20)
    }
}
```

**Expected:** `backed.pointee == 20` (read from `&values[2]`).
**Observed on Linux release:** `backed.pointee` returns a different value;
the load reads from the wrong address.

## Reduction Path

The bug was first observed in `swift-affine-primitives` with a much larger
shape (`Tagged<Pointee, Ordinal>.Offset`, `Affine.Discrete.Vector`, a
`Carrier.Protocol` witness, `~Copyable` generic parameters, package operator
overloads). Aggressive single-pass reduction stripped all of these. **None
were load-bearing.** What remains is the minimum trigger:

- stdlib `UnsafeMutablePointer<Int>` + `.advanced(by:)`
- a 10-line `Vec` struct wrapping a single `Int`
- user-authored `+` / `-` operators that call `.advanced(by:)`

## Failed Source-Level Fix Attempts

Three candidate fixes were applied symmetrically to the original failing
operators in `swift-affine-primitives`. None resolved the bug:

| # | Fix | Result on Linux 6.3 release + 6.4-dev nightly |
|---|-----|-----------------------------------------------|
| 1 | Explicit local `let offset = Int(bitPattern: rhs)` inside operator | Still fails |
| 2 | Swap `@_transparent` → `@inlinable` | Still fails |
| 3 | Wrap arithmetic in `withExtendedLifetime(rhs) { … }` | Still fails |

The fixes were cumulative. None addressed the bug because the miscompile is at
the call-site `.pointee` read, not at the operator body's pointer arithmetic.

## Heisenbug Character

Any diagnostic instrumentation that reads the result pointer between the
operator call and the `.pointee` read structurally masks the bug:

- Print statements between operator and load
- Intermediate `let _ = UInt(bitPattern: backed)` materialization (single-line — **not** sufficient on its own, but multiple intermediate let-bindings together do mask)
- A `print()` of the address inside a `#expect` message string

The reducedRepro above omits all such instrumentation. Adding any of them on
Linux release heals the test.

## Workaround for Consumers

Bypass the user-authored operator and call `.advanced(by:)` directly:

```swift
// Instead of:
let backed = advanced - Vec(2)
// Use:
let backed = advanced.advanced(by: -2)
```

The stdlib direct-call form is not affected.

## CI Status

| Platform | Configuration | Status |
|----------|---------------|--------|
| macOS | Swift 6.3 release | Passes |
| Linux | Swift 6.3 release | **FAILS** |
| Linux | Swift 6.4-dev nightly release | **FAILS** |
| Linux | Swift 6.3 debug | Passes |
| Windows | Swift 6.3 release | Passes |

CI workflow at `.github/workflows/ci.yml` runs all five legs on every push.

## Suggested Labels

`bug`, `optimization`, `codegen`, `linux`, `unsafe-pointer`, `release-mode`

## Original Discovery

Bug surfaced in `swift-institute/swift-primitives/swift-affine-primitives` CI
during release-mode test of `UnsafeMutablePointer<T> - Tagged<T, Ordinal>.Offset`
operator. See `swift-affine-primitives/Research/swift-issue-pointer-arithmetic.md`
for the full investigation trail, including the failed source-level fix
attempts and the reduction sequence.
