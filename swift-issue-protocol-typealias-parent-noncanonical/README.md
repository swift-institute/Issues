# Swift Issue: "Forming a CanType out of a non-canonical type!" for an existential whose protocol is named through a typealias of its parent

**Record:** [swift-institute/Issues#21](https://github.com/swift-institute/Issues/issues/21) (`upstream-candidate`).

**Upstream:** open [swiftlang/swift#86202](https://github.com/swiftlang/swift/issues/86202), the same defect, filed 2025-12-24 with the two-package reproduction kept under `evidence/`. Its title and findings say the crash is Windows-only and needs a package boundary; this reduction shows neither is true. The record drafts a comment for #86202 with the one-file reproduction and the matrix. **NOT POSTED:** posting needs Coen's explicit yes.

**Classification:** compiler assertion. The source is valid. The assertion is compiled out of release toolchains, which accept the file; the swift.org Windows toolchain is built with assertions, so in the fleet only the Windows leg fails.

The folder name is from the first report, which saw it on Windows only. The defect is not Windows-specific.

## Minimal reproducer

[`repro.swift`](repro.swift):

```swift
enum E { protocol P {} }
typealias A = E
func f(_: A.P) {}
```

```sh
swiftc -g repro.swift
```

**Actual** (6.4.x-snapshot-2026-10-23, macOS arm64, `+assertions`):

```
Assertion failed: (isActuallyCanonicalOrNull() && "Forming a CanType out of a non-canonical type!"), function CanType, file Type.h, line 421.
3.	While evaluating request IRGenRequest(IR Generation for file "repro.swift")
4.	While emitting IR SIL function "@$s5repro1fyyAA1EO1P_pF".
5.	While mangling type for debugger type 'any A.P'
frame 0: swift::Mangle::ASTMangler::appendType
frame 1: swift::Mangle::ASTMangler::mangleTypeForDebugger
frame 2: IRGenDebugInfoImpl::getMangledName
frame 3: IRGenDebugInfoImpl::getOrCreateType
```

On main-snapshot-2026-10-27 the same assertion fires earlier, while verifying the SIL function (`SILVerifier::checkLegalSILType` → `Type::findIf` → `Traversal::visitNominalType` → a `CanType` callback, whose symbol is a folded alias named after IRGen's `isHoistable`), and there it needs no `-g`. On main the bad type already exists after type checking: `_ = 0 is A.P` asserts with `-typecheck` (independent review).

**Expected:** the file compiles.

## Minimal conditions

Every row is one change against `func f(_: any A.P) {}` (the spelling before the review dropped `any`), run on 6.4.x-snapshot-2026-10-23 and main-snapshot-2026-10-27 (macOS arm64, 2026-10-30, `swiftly run swiftc <flags> -c <file> -o /dev/null +<toolchain>`):

| Change | 6.4.x | main |
|---|---|---|
| none (`-g`) | asserts | asserts |
| no `-g` | compiles | asserts |
| `-gline-tables-only` | compiles | asserts |
| `-O -g` | asserts | asserts |
| `any E.P`: the parent spelled without the typealias | compiles | compiles |
| `any P` unqualified, inside `extension A` | compiles | compiles |
| `some A.P` | compiles | compiles |
| `<T: A.P>` | compiles | compiles |
| a nested `struct S` and `A.S` instead of a protocol | compiles | compiles |
| `A.P` without `any` (now `repro.swift`) | asserts | asserts |
| `struct E` instead of `enum E` | asserts | asserts |
| `P` declared in `extension E` | asserts | asserts |
| `E` nested one level deeper, `typealias A = E.F` | asserts | asserts |
| `any E.F.P` with that deeper nesting, no typealias | compiles | compiles |
| `[any A.P]` | asserts | asserts |
| `(any A.P)?` as a global | asserts | asserts |
| `typealias B = A.P`, used as `any B` | asserts | asserts |
| `any A.P & Sendable` | asserts | compiles |
| `(any A.P).Type` | compiles | asserts |

So the ingredients are a protocol nested in a type, a typealias for that type, and an existential of the protocol spelled through the typealias. Not ingredients: a package or module boundary, `extension`, `enum` versus `struct`, the `any` keyword, the optimization level, Windows.

## Cause

Inferred, not confirmed in the compiler source: the typealias sugar on the protocol type's parent (`A` for `E`) survives inside a type that is then treated as canonical. The main-snapshot stacks show the SIL verifier's and the type checker's type walks reaching a `CanType` callback through `visitNominalType`, which visits a nominal type's parent. `ProtocolType::get` and `TypeBase::computeCanonicalType` on swiftlang/swift `main` both canonicalize the parent correctly, so the non-canonical type is formed somewhere else. That place was not found.

## Toolchains

| Toolchain | `swiftc --version` | Result | Where |
|---|---|---|---|
| 6.4.x-snapshot-2026-10-23 | Apple Swift version 6.4.4-dev (LLVM 33d4562f9d6134f, Swift a7875ddba7eabcb) | asserts (IRGen) | local, macOS arm64 |
| main-snapshot-2026-10-27 | Apple Swift version 6.5-dev (LLVM 7211ac1d2aee144, Swift b5fe9234c4eb9b4) | asserts (SIL verifier) | local, macOS arm64 |
| 6.4.1 | Apple Swift version 6.4.1 (swift-6.4.1-RELEASE) | compiles (no assertions) | local, macOS arm64 |
| xcode-27.2 | Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1) | compiles (no assertions; also with `-Xfrontend -sil-verify-all`) | local, macOS arm64 |
| windows-6.4.1 | Swift version 6.4.1 (swift-6.4.1-RELEASE), `+Asserts` | asserts | CI, Windows x86_64, toolchain-matrix run 41084925664 |
| windows-6.4.2 | Swift version 6.4.2 (swift-6.4.2-RELEASE), `+Asserts` | asserts | CI, Windows x86_64, toolchain-matrix run 41084925664 |

Earlier Windows observations of the original two-package shape: Swift 6.0.3 (2025-12, swiftlang/swift#86202), 6.4.0 (platform-probes runs 38137662398 and 38138335935, 2026-10-11).

## Where the fleet hits it

`swift-compositions/swift-webpage`, Windows release leg, Swift 6.4.1 `+Asserts` (CI run 39670486834, head `b7e95aa`, 2026-10-21):

```
Assertion failed: isActuallyCanonicalOrNull() && "Forming a CanType out of a non-canonical type!", file …\swift\include\swift/AST/Type.h, line 421
3.	While evaluating request IRGenRequest(IR Generation for file "…\Sources\Webpage\NavigationBar.swift")
4.	While emitting IR SIL function "@$s7Webpage13NavigationBarV10MobileMenuV4bodyQrvg…".
5.	While mangling type for debugger type 'HTML.View'
```

The trigger there is `public typealias NavItem = HTML.View` and `let items: [any NavItem]` in `NavigationBar.MobileMenu`. `HTML` is a typealias for the enum `WHATWG.HTML`, and `View` is a protocol nested in it, so `any NavItem` is `any A.P` through two typealiases. The Windows log names the debugger type `HTML.View`, as the reduction's `typealias B = A.P` row does. The macOS and Linux legs build the same revision because their toolchains have no assertions.

Still failing on swift-webpage `main` `546c587` (CI run 41079843700, full workflow, 2026-10-30): the Windows leg, now Swift 6.4.2 `+Asserts`, asserts seven times at `NavigationBar.swift:148`; Linux 6.4, Linux release, Linux traits-off and macOS are green. A fresh clone of `546c587` built locally with `swift build --target Webpage` on the 6.4.x-snapshot-2026-10-23 (macOS arm64) asserts the same way, so the package reproduces off Windows too.

The original records show the same shape: `any HTML.View` in `HTML.AnyView` (this folder's `evidence/`), and `any PDF.HTML.Style.Modifier` with `PDF` a typealias for `ISO_32000` ([`../swift-issue-noncanonical-existential-windows-debuginfo-ice`](../swift-issue-noncanonical-existential-windows-debuginfo-ice)). That record's single-file control used no typealias root, which is why it compiled.

## Workaround

In swift-webpage's own source, yes (observed on macOS arm64 with the 6.4.x-snapshot-2026-10-23 only, in a scratch clone, nothing pushed): spell the existentials through the canonical root instead of the `HTML` typealias, `public typealias NavItem = WHATWG.HTML.View` in `NavItem.swift` and `any WHATWG.HTML.View` for the six `any HTML.View` in `NavigationBar.swift` (7 lines in 2 files). `swift build --target Webpage` then succeeds; unmodified, it asserts. Not checked on Windows CI or on a main snapshot, where the SIL-verifier path may reach spellings that 6.4's debug-info path does not. Not applied.

`-Xswiftc -gnone` (the earlier record's workaround) avoids it on 6.4 only, and gives up debug info; on main the assertion fires without `-g`.

The earlier lanes' rewrites (a named `Item` subview, `map`, imperative construction) kept the `HTML.View` spelling, which is why they all still asserted.

## Harness

`Tests/Reproducer Tests.swift` and `Sources/Reproducer/main.swift` compile `repro.swift` with `swiftc -g -c` in a child process ([ISSUE-029]). A toolchain without `+assertions` is inconclusive (the test passes without a known issue, the probe exits 0). Checked on 2026-10-30 (macOS arm64): with Xcode 27.2's `swiftc` the test passes plainly; with the 6.4.x snapshot's `swiftc` first on `PATH` it passes with one known issue and the probe exits 1.

## History

- 2025-12-24: filed upstream as swiftlang/swift#86202 from `coenttb/swift-issue-windows-existential-crash` and its `-other-package` (Swift 6.0.3, Windows). That report holds that the package boundary is required.
- 2026-07-27: clean-copied here as a staged dossier; sources and provenance in `evidence/` (`source-provenance.json`). The second package no longer exists on GitHub; `.github/workflows/platform-probes.yml` rebuilds it from `evidence/fixtures/other-package`.
- 2026-10-11: still asserts on Windows Swift 6.4.0 (platform-probes runs 38137662398 and 38138335935).
- 2026-10-30: reduced to `repro.swift` from swift-webpage's Windows failure; shown to need neither Windows nor a package boundary, only an assertions build.
