# [Compiler][ICE] Windows debug-info mangling aborts on an existential whose root is another package's namespace typealias

Characterization: [CHARACTERIZATION.md](CHARACTERIZATION.md). Sibling: [swift-issue-windows-existential-crash](../swift-issue-windows-existential-crash) (Issues#21, the `any HTML.View` shape).

## Summary

On Windows with an assertions toolchain, a debug build aborts with `Assertion isActuallyCanonicalOrNull()` (`AST/Type.h:421`) while IRGen mangles the debugger type of `any PDF.HTML.Style.Modifier`, when `PDF` is a typealias declared in another package (`public typealias PDF = ISO_32000`, as swift-pdf-standard does). The written existential keeps the typealias sugar at its root, which is the non-canonical type the mangler rejects.

## Minimal reproduction

The sources are exact copies of swift-compositions/swift-pdf `9d576dabb05d41b73de2a9199c97d6fc4d5c8040` (`.github/repro/` and the workflow that ran them). The package boundary is part of the trigger, so it is kept.

```console
swift build -c debug --package-path evidence/source/cross-package/crash --target CrashModule    # aborts
swift build -c debug --package-path evidence/source/cross-package/crash --target RespellModule  # control: clean
swiftc -Onone -g -c evidence/source/noncanonical-existential-debuginfo.swift -o repro.o          # control: clean
```

`evidence/source/windows-existential-repro.yml` is the workflow that ran this matrix in swift-pdf; its paths are the ones it had there (`.github/repro/…`).

## Environment matrix

| Variant | Swift 6.3.3 (Windows, +Asserts, debug) | Swift 6.4 (Windows, +Asserts, debug) |
| --- | --- | --- |
| cross-package (`CrashModule`) | STILL FIRING | STILL FIRING |
| respell-canonical (`RespellModule`) | CLEAN | CLEAN |
| single-file | CLEAN | CLEAN |

Last measured: swift-pdf run 32489398734, 2026-08-21. macOS and Linux do not fire (no assertions, or no Windows debug-info path).

## Workaround

Spell the existential at the affected downcasts through the canonical root (`any ISO_32000.…`), as `RespellModule` does.

## Closure gate

Close when `CrashModule` builds cleanly on the Windows assertions toolchain the fleet uses, re-measured with the three commands above.
