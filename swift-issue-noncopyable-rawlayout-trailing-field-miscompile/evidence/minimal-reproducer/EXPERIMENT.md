# Minimal Reproducers for @_rawLayout Compiler Bugs

> **UPDATE (2026-03-22)**: Bug 2 was subsequently reproduced in `../copypropagation-nonescapable-mark-dependence/`. The 7 patterns here failed because they tested general `~Copyable`/`@_rawLayout` patterns without the specific `~Escapable` + `@_lifetime(borrow)` ingredient that generates `mark_dependence`. Bug 2 root cause has been fixed by removing `~Escapable` from Property.View.

<!--
---
status: Bug 1 REPRODUCES, Bug 2 DOES NOT REPRODUCE (see copypropagation-nonescapable-mark-dependence for successful reproducer)
date: 2026-03-21
toolchain: Swift 6.2.4 (swiftlang-6.2.4.1.4 clang-1700.6.4.2, arm64 macOS 26)
supports: release-build-resolution-handoff-v2.md Step 4
---
-->

## Question

Can we create standalone, zero-dependency packages that reproduce the two compiler bugs blocking `swift build -c release` without `-Xfrontend` flags?

## Summary

**Bug 1 (LLVM verifier crash): REPRODUCES.** Minimal standalone reproducer found.

**Bug 2 (CopyPropagation ownership crash): DOES NOT REPRODUCE.** Consistent with all prior experiments. Context-sensitive per [EXP-004a] — requires the full production dependency graph (5+ layers of @inlinable typed infrastructure cascading through cross-module generic specialization).

## Bug 1: LLVM Verifier Crash

### Minimal Trigger

Three files across two modules:

**Module A** (`Bug1Core/Types.swift`):
```swift
public enum Container<Element: ~Copyable> {
    @_rawLayout(likeArrayOf: Element, count: capacity)
    public struct Inline<let capacity: Int>: ~Copyable {
        public init() {}
        deinit {}
    }
}
```

**Module B** (`Bug1Middleware/Wrappers.swift`):
```swift
import Bug1Core

public struct Buffer<Element: ~Copyable>: ~Copyable {
    var _a: Container<Element>.Inline<8>
    var _b: Container<Element>.Inline<4>

    public init() {
        self._a = Container<Element>.Inline<8>()
        self._b = Container<Element>.Inline<4>()
    }
}
```

### Build Command

```bash
cd rawlayout-minimal-reproducer/
rm -rf .build && swift build -c release --target Bug1Consumer
```

### Expected Output

```
signal 6
Instruction does not dominate all uses!
  ...
Running pass "verify" on module "...Bug1Middleware.build/Wrappers.swift.o"
fatal error encountered during compilation
```

### Minimal Requirements (all must be present)

| Requirement | Remove it | Result |
|-------------|-----------|--------|
| Generic enum wrapper (`Container<Element>`) | Top-level `@_rawLayout` | Builds fine |
| `@_rawLayout(likeArrayOf: Element, count: capacity)` | Non-@_rawLayout struct | Builds fine |
| Value generic (`let capacity: Int`) | Fixed-size type | Builds fine |
| Explicit `deinit` | Compiler-synthesized deinit | Builds fine |
| 2+ fields in consumer module | 1 field | Builds fine |
| Release mode (`-O`) | Debug mode | Builds fine |

### New Findings

1. **@inlinable NOT required** — neither on the core type's init nor the consumer struct. The crash is purely structural.
2. **Cross-module threshold is 2 fields** — not 3. This is lower than the within-module struct-body threshold documented in prior experiments.
3. **Same type, different capacities crashes** — `Inline<8>` + `Inline<4>` of the same type triggers it. No need for distinct types.
4. **The crash is in the consumer module** — Bug1Middleware crashes, not Bug1Core. The @_rawLayout type metadata from Bug1Core is incorrectly lowered to LLVM IR when the consuming module's struct destructor needs to destroy 2+ @_rawLayout fields.

### Important Caveat: Reproducer vs Production Trigger Paths

This reproducer captures the **consumer-module 2-field** trigger path. The production crash in Buffer Primitives Core uses a **different** trigger path: extension-file defined @_rawLayout+deinit types under WMO. The `AnyObject?` triviality workaround fixes THIS reproducer but does NOT fix the production crash. See `rawlayout-llvm-verifier-crash/EXPERIMENT.md` "AnyObject? Workaround Test" for details.

The reproducer is still valuable for filing against swiftlang/swift — it demonstrates the same underlying bug (triviality misclassification for cross-module @_rawLayout types) via a simpler trigger path.

## Bug 2: CopyPropagation Ownership Crash

### Status: DOES NOT REPRODUCE

Tried the following patterns, none triggered the crash:

| Pattern | Description | Result |
|---------|-------------|--------|
| ~Escapable view + _read coroutine + loop | `@_lifetime(borrow self)` _read, accessed in loop | Builds fine |
| ~Escapable view + enum switch | View accessed in enum switch branches | Builds fine |
| ~Escapable view + chained coroutines | 3-layer _read coroutine chain | Builds fine |
| ~Copyable enum + consuming switch | Consume payload + element in switch case | Builds fine |
| Bitmap-conditional move in loop | `if bitmap[i] { move(at: i) }` loop | Builds fine |
| @_rawLayout dependency + enum consuming | Import Bug1Core, SmallBuffer with enum | Triggers Bug 1, not Bug 2 |
| -disable-llvm-verify + enum consuming | Suppress Bug 1, test enum consuming | Builds fine |

### Conclusion

Bug 2 is context-sensitive. The production crash requires the interaction of:
- 5+ layers of @inlinable typed infrastructure from `swift-primitives` tier system
- Cross-module generic specialization cascading through the dependency graph
- @_rawLayout types with deinit in the serialized SIL context
- ~Copyable enum switches with conditional element consumption

A standalone reproducer cannot replicate this interaction. Filing against swiftlang/swift should focus on Bug 1 (which reproduces) and reference Bug 2 as a secondary issue observed in the production codebase with `-Xfrontend -disable-llvm-verify`.

## Build Protocol

```bash
# Bug 1 (REPRODUCES):
cd rawlayout-minimal-reproducer/
rm -rf .build && swift build -c release --target Bug1Consumer
# Expected: signal 6, "Instruction does not dominate all uses!"

# Bug 1 (middleware alone also crashes):
rm -rf .build && swift build -c release --target Bug1Middleware
# Expected: same crash

# Bug 2 (DOES NOT REPRODUCE):
rm -rf .build && swift build -c release --target Bug2Consumer
# Expected: builds successfully (with -disable-llvm-verify)

# Debug mode (both bugs absent):
rm -rf .build && swift build --target Bug1Consumer
rm -rf .build && swift build --target Bug2Consumer
# Expected: both build fine
```

## Cross-References

- [release-build-resolution-handoff-v2.md](../../Research/release-build-resolution-handoff-v2.md) — Step 4: Build minimal reproducer
- [rawlayout-llvm-verifier-crash](../rawlayout-llvm-verifier-crash/) — Consolidated experiment for Bug 1
- [rawlayout-sil-ownership-crash](../rawlayout-sil-ownership-crash/) — Consolidated experiment for Bug 2
- [release-mode-llvm-verifier-crash-diagnosis.md](../../Research/release-mode-llvm-verifier-crash-diagnosis.md) — Full diagnosis
