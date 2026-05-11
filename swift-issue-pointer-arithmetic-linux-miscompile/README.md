# Swift Issue: Linux Release-Mode Pointer Arithmetic Miscompile

**Bug Report:** Pending — issue body drafted, awaiting filing at swiftlang/swift.

Minimal reproducer for a Linux-only release-mode codegen miscompile in which a
`.pointee` read after a user-authored pointer arithmetic operator returns the
value at the wrong address. **Gated by the experimental Swift feature
`Lifetimes`** — without that swiftSetting, the same source compiles to
correct code on every platform.

## Bug Summary

User-authored `+` / `-` operator overloads on `UnsafeMutablePointer<Int>` that
wrap `.advanced(by:)` produce correct pointer values, but the subsequent
`.pointee` load reads from the wrong address. Fires only when the enclosing
target has `.enableExperimentalFeature("Lifetimes")` enabled in its SwiftPM
swiftSettings.

The arithmetic itself is correct — printing `UInt(bitPattern:)` of the
intermediate pointers between the operator call and the load yields the
expected addresses. The miscompile is at the load codegen.

## Demonstration

This directory contains two test targets that share **byte-identical** source
files (`PointerArithmeticTests.swift`):

| Target | swiftSettings | Linux 6.3 release | macOS | Windows |
|--------|--------------|-------------------|-------|---------|
| `WithLifetimes` | `.enableExperimentalFeature("Lifetimes")` | **FAILS** | passes | passes |
| `WithoutLifetimes` | _(none)_ | passes | passes | passes |

The diff between the two targets is exactly one line in the top-level
`Package.swift` (the swiftSettings list). The Swift source itself is
identical. CI in this repo runs both side-by-side on every push, so the
demonstration is self-contained: a maintainer cloning the repo sees the
bug fire and a paired control proving the trigger.

## Reproduction

```bash
git clone https://github.com/swift-institute/Issues.git
cd Issues
swift test -c release
```

On Linux 6.3 release: `WithLifetimes.reducedRepro` FAILS;
`WithoutLifetimes.reducedRepro` passes. On macOS / Windows / Linux debug:
both pass.

To narrow further:

```bash
swift test -c release --filter WithLifetimes
swift test -c release --filter WithoutLifetimes
```

## Environment

- **Swift versions:** 6.3 stable, 6.4-dev nightly
- **Platform:** Linux (Ubuntu jammy, swift:6.3 and swiftlang/swift:nightly-main-jammy containers)
- **Works on:** macOS (any build), Linux debug, Windows
- **Trigger:** `.enableExperimentalFeature("Lifetimes")` in target's swiftSettings

## Minimal Code

Both `WithLifetimes/PointerArithmeticTests.swift` and
`WithoutLifetimes/PointerArithmeticTests.swift` (byte-identical):

```swift
import Testing

struct Vec {
    let raw: Int
    init(_ raw: Int) { self.raw = raw }
}

func + (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    lhs.advanced(by: rhs.raw)
}

func - (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    lhs.advanced(by: -rhs.raw)
}

@Suite
struct PointerArithmeticReduced {
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
}
```

**Expected:** `backed.pointee == 20` (read from `&values[2]`).
**Observed on Linux release with `.Lifetimes` enabled:** `backed.pointee`
returns a different value; the load reads from the wrong address.

## Reduction Path

The bug was first observed in `swift-affine-primitives` with a much larger
shape (`Tagged<Pointee, Ordinal>.Offset`, `Affine.Discrete.Vector`, a
`Carrier.Protocol` witness, `~Copyable` generic parameters, package operator
overloads, 10 swiftSettings). Aggressive reduction stripped:

- All wrapper types (`Tagged`, `Ordinal`, `Vector`, `Carrier.Protocol`)
- The `~Copyable` generic parameter
- All package operator overloads
- 9 of the 10 swiftSettings

What remains is the minimum trigger: stdlib `UnsafeMutablePointer<Int>` +
10 lines of `Vec`/operator code + `.enableExperimentalFeature("Lifetimes")`.

The Lifetimes setting was identified via bisection: commit `cc72949`
narrowed from 10 settings to 1; each of the other 9 settings was confirmed
unnecessary by exclusion.

## Heisenbug Character

Any diagnostic instrumentation that reads the result pointer between the
operator call and the `.pointee` read structurally masks the bug:

- Print statements between operator and load
- Multiple intermediate `let _ = UInt(bitPattern: backed)` materializations
- `print()` of the address inside a `#expect` message string

The `reducedRepro` above omits all such instrumentation. Adding any of them
on Linux release with `.Lifetimes` enabled heals the test.

## Workaround for Consumers

Drop `.enableExperimentalFeature("Lifetimes")` from the affected target's
swiftSettings, OR bypass the user-authored operator and call `.advanced(by:)`
directly:

```swift
// Instead of:
let backed = advanced - Vec(2)
// Use:
let backed = advanced.advanced(by: -2)
```

The stdlib direct-call form is not affected by the miscompile.

## CI Status

The CI workflow at `.github/workflows/ci.yml` (top-level of the Issues repo)
runs both targets on every push. The `Ubuntu (Swift 6.3, release)` and
`Ubuntu (Swift 6.4-dev nightly, release)` legs are permanently red until
the upstream fix lands — that red leg IS the bug's running evidence.

## Suggested Labels

`bug`, `optimization`, `codegen`, `linux`, `unsafe-pointer`, `release-mode`,
`Lifetimes`, `experimental-feature`

## Original Discovery

Bug surfaced in `swift-institute/swift-primitives/swift-affine-primitives` CI
during release-mode test of `UnsafeMutablePointer<T> - Tagged<T, Ordinal>.Offset`
operator. The affine-primitives target has `.Lifetimes` (and 9 other features)
enabled per the swift-institute ecosystem-wide feature flags.
