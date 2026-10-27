# Swift Issue: SendNonSendable aborts in `Partition::merge` on an IIFE around a borrowing `@_lifetime` init

**Upstream:** **NOT FILED.** This directory is the institute's record.

**Classification:** Compiler crash (signal 6) in the mandatory `SendNonSendable`
SIL pass, inside region analysis (`RegionAnalysisFunctionInfo::runDataflow` →
`Partition::merge`). The source is valid. Debug (`-Onone`) is enough.

## Minimal reproducer

Two modules. `Sources/Reproducer/ReproLib.swift.txt`:

```swift
public struct Target: ~Copyable {
    public init() {}
}

public struct View<Base: ~Copyable>: ~Copyable, ~Escapable {
    @_lifetime(borrow base)
    public init(_ base: borrowing Base) {}
}
```

`Sources/Reproducer/Crash.swift.txt` (compiled as `main.swift`):

```swift
import ReproLib

func crashingFunction() {
    let target = Target()
    _ = { _ = View(target) }()
}

crashingFunction()
```

```bash
xcrun swiftc -emit-module -parse-as-library -module-name ReproLib -swift-version 6 \
    -enable-experimental-feature Lifetimes \
    ReproLib.swift -emit-module-path ReproLib.swiftmodule -o /dev/null
xcrun swiftc -c -swift-version 6 -Onone -enable-experimental-feature Lifetimes \
    -I . main.swift -o main.o
```

**Actual** (Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1), macOS arm64, exit 134):

```
4.	While running pass #32 SILFunctionTransform "SendNonSendable" on SILFunction "@$s4main16crashingFunctionyyFyyXEfU_".
6  swift-frontend  swift::Partition::merge(swift::PartitionPrimitives::Element, swift::PartitionPrimitives::Element, bool) + 244
7  swift-frontend  swift::RegionAnalysisFunctionInfo::runDataflow() + 5640
8  swift-frontend  swift::RegionAnalysis::newFunctionAnalysis(swift::SILFunction*) + 3940
9  swift-frontend  (anonymous namespace)::SendNonSendable::run() + 268
```

Full log: `evidence/crash-6.4.2.txt`.

**Expected:** the caller compiles. `Target` is borrowed for the duration of the
closure, and the closure does not escape.

## Trigger characterization

Checked on 6.4.2 by removing one ingredient at a time, with the same flags:

| Ingredient | Removed / replaced by | Result on 6.4.2 |
|---|---|---|
| the IIFE | `_ = View(target)` directly in the function body (the workaround) | compiles |
| enclosing function body | the same IIFE as top-level code | compiles |
| `Target: ~Copyable` | `Target` Copyable | compiles |
| `View: ~Copyable` | `View<Base: ~Copyable>: ~Escapable` | compiles |
| `View` generic over `Base` | non-generic `View` with `borrowing Target` | compiles |
| Swift 6 language mode | `-swift-version 5` | compiles |
| `public` declarations | all `internal`, one file | compiles |
| the separate module | both types `public`, same file as the caller | **still crashes** |

So on 6.4.2 the second module is not needed, but the `public` access is. The
6.3.1 record (`evidence/original-main.swift`) said both types had to live in a
separate module. The harness keeps the two-module shape of the original.

`~Escapable` and `@_lifetime` come as a pair: the compiler rejects either one
without the other. `-O`, `@unsafe`, strict memory safety and stored properties
are not needed.

## Toolchains

| `swiftc --version` | Result |
|---|---|
| Apple Swift version 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102) — Xcode 26.4.1 | crashes (`evidence/build-6.3.1.txt`) |
| Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1) — Xcode 27.2 | crashes (`evidence/crash-6.4.2.txt`) |

Only macOS arm64 was run locally. Linux and Windows were not run; CI covers them.

## Workaround

Bind the view in the enclosing scope instead of inside an immediately-invoked
closure:

```swift
func workaroundFunction() {
    let target = Target()
    _ = View(target)
}
```

## Harness

`Tests/Reproducer Tests.swift` and `Sources/Reproducer/main.swift` stage both
sources in a temp directory, build `ReproLib` with `swiftc -emit-module`, then
compile the caller with `swiftc -c -Onone`, all in child processes, because the
caller aborts the compiler and cannot be a compiled target. "Fired" means swiftc
exited non-zero and its output names the `"SendNonSendable"` pass. A clean
compile means absent. Anything else is inconclusive and does not fail.

The bug fires on every release toolchain tested, so `withKnownIssue` uses
`when: { true }`. The test flips red once the caller compiles.

Local evidence for the harness (6.4.2, macOS arm64):

- `swiftc main.swift -o probe && ./probe` → `BUG FIRED: swiftc aborted in the SendNonSendable pass.`, exit 1.
- The same probe with `Crash.swift.txt` replaced by the workaround → `The caller compiled cleanly — the bug is FIXED.`, exit 0.

## Provenance

Ported from `swift-institute/Experiments/sendnonsendable-iife-borrowing-init-crash`
at commit `f1c4db4d390c12af5ec454dfb506feaa4ec5e841`. Found on 2026-04-21 while
writing a unit test for `Property.View.init(_ base: borrowing Base)` in
swift-property-primitives (commit `2e0e624`). The original sources and the 6.3.1
build log are in `evidence/`.
