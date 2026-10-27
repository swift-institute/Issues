# Swift Issue: ASTScope verifier "child overlaps previous child" when a member-attribute macro returns two attributes

**Upstream:** **NOT FILED.** The record is [swift-institute/Issues#157](https://github.com/swift-institute/Issues/issues/157) (`upstream-candidate`), with a drafted new issue for swiftlang/swift. Its duplicate search found none; [swiftlang/swift#92229](https://github.com/swiftlang/swift/issues/92229) is related (same verifier function, malformed-source trigger). Filing needs Coen's explicit yes, and the record waits on [Issues#182](https://github.com/swift-institute/Issues/issues/182), the gate change for two-command macro-plugin reproductions.

**Classification:** compiler abort in an assertions-only check. The source is valid. When an attached member-attribute macro returns two or more custom attributes for one member, the two `CustomAttributeScope`s for the generated attributes are added in reverse source order and the ASTScope verifier aborts. Release toolchains do not run that verifier and accept the file. It is not Windows-only: every assertions build tried aborts.

## Minimal reproducer

`Sources/Reproducer/Crash.swift.txt` (the lane's `final/scope.swift`, kept in `evidence/lane/final/`) is one file with two roles. Built with `-D PLUGIN` it is a macro plugin that speaks the compiler's plugin protocol directly, so swift-syntax is not needed: `M` returns `@A @A` for every member and `A`, a peer macro, expands to nothing. Built without the flag it is the client:

```swift
@attached(memberAttribute) macro M() = #externalMacro(module: "P", type: "M")
@attached(peer) macro A() = #externalMacro(module: "P", type: "A")

@M struct S { var x: Int }
```

```bash
swiftc -D PLUGIN repro.swift -o plugin
swiftc -typecheck -load-plugin-executable plugin#P repro.swift
```

**Actual (assertions builds):**

```
Abort: function abortWithVerificationError at ASTScopePrinting.cpp:73
ASTScopeImpl verification error in source file 'repro.swift':
child overlaps previous child:
CustomAttributeScope 0x55b015bfdc68, [1:1 - 1:2]
***Previous child
CustomAttributeScope 0x55b015bfdc68, [1:4 - 1:5]
***Parent node***
NominalTypeBodyScope 0x55b015bfdb68, [43:13 - 43:26] 'S'
```

(Line 78 instead of 73 on 6.4.x builds.) Both ranges are in the macro's expansion buffer.

**Expected:** the client type-checks, as it does on release toolchains.

## Trigger characterization

From the lane (runs 39784950734 and 39786015934) and two review rounds (39790505398 and 39795615821), on Windows 6.4.1, the Linux nightly and the macOS snapshots (`evidence/ci/`, variant files in `evidence/review/` and `evidence/lane/astscope/`):

| Ingredient | Removed / replaced by | Result |
|---|---|---|
| two generated custom attributes (`@A @A`, `@A @B`, or 14 in swift-recursion) | one (`@A`; `rvw1/v06_single_A_control.swift`) | accepted |
| a member with a type to look up (`var x: Int`) | `var x = 0` (`rvw1/v02_no_type_annot.swift`) | accepted |
| the member's kind | `let`, a nested enum or struct, a member function | still aborts |
| the peer macro declaration | dropped, with `M` always returning `@A @A` (`rvw/v20_noA_always.swift`) | still aborts (exit 139 on Linux) |
| custom attributes | `@MainActor @A` | still aborts; `@MainActor` or `@available` alone does not |
| `-typecheck` | `-c` / a full compile | still aborts |
| the plugin's capability reply, `protocolVersion`, `diagnostics` | removed | plugin protocol fails differently |
| a plugin build | the toolchain's own `@Observable` with a written `@MainActor` property | accepted; no one-command form found |

## Toolchains

From run 39788628757 (lane head `0f646c6a6a605a799991e7a4aff234542ea73546`), the reproduction exactly as drafted, each in a fresh directory:

| Toolchain | Result |
|---|---|
| macOS main-snapshot-2026-10-17, Swift 6.5-dev (f62414fd1d17227), `+assertions` | aborts |
| macOS 6.4.x-snapshot-2026-10-20, Swift 6.4.4-dev (90b3468f3de7d1f), `+assertions` | aborts |
| Windows Swift 6.4.1 (swift-6.4.1-RELEASE), `+assertions` | aborts (exit 132) |
| Linux `swiftlang/swift:nightly-main-jammy`, Swift 6.5-dev (f62414fd1d17227), `+assertions` | aborts (exit 134) |
| macOS swift.org 6.4.1 release, Linux `swift:6.4.1-noble`, Xcode 26.6 (Swift 6.3.3) | accepted (no assertions) |
| Apple Swift 6.4.2 (swiftlang-6.4.2.1.9), Xcode, macOS arm64 | accepted (no assertions); local, this port |

**Not run locally.** This Mac has only Xcode's Swift 6.4.2, which has no assertions. `-Xfrontend -enable-ast-verifier` and `-dump-scope-maps expanded` do not make it abort either (`evidence/local-macos-6.4.2.txt`). The firing evidence is CI only.

## Workaround

None at the macro's use site. The macro must return at most one generated attribute per member. In swift-birecursive the test fixtures write the prerequisite attributes by hand so the macro emits only the missing one. In swift-recursion that would mean replacing its composition of derivation macros (Issues#113, 22 Oct).

## Harness

`Tests/Reproducer Tests.swift` and `Sources/Reproducer/main.swift` build the plugin and type-check the client in child processes, with the record's two commands. The signature is `child overlaps previous child`. A plugin that fails to build makes the probe inconclusive.

The bug fires only on assertions builds, so `withKnownIssue` uses `when: { assertionsToolchain() }`, which is true when `swiftc --version` prints `+assertions`. On an assertions toolchain the test is green while the abort fires and turns red once the client is accepted. On a release toolchain the body runs unguarded and passes. `main.swift` exits 1 when the abort fires and 0 otherwise; on a release toolchain it says the result is inconclusive.

Like the exemplar, the probes run only where `/usr/bin/env swiftc` exists (macOS, Linux) and skip Windows, although the plugin source has its own Windows branch. On current Issues CI the legs that run tests have no assertions (macOS, Linux release) or skip these probes (Windows 6.4), so the harness never sees the bug fire there.

How the harness was checked locally (`evidence/local-macos-6.4.2.txt`): on Xcode 6.4.2 the test passes and the probe exits 0 (inconclusive). A stand-in `swiftc` that reports `+assertions` and replays the abort text recorded on CI (`evidence/stub/`) makes the test record the known issue and the probe exit 1. The same stand-in exiting 0 makes the test fail with "Known issue was not recorded" and the probe exit 0. The stand-in compiles nothing; it only shows the harness reads both outcomes.

## Provenance

Reduced on 22 Oct 2026 on the private repository `swift-institute/windows-exception-29-reproducer`, branch `lane/astscope-member-attribute` at `0f646c6a6a605a799991e7a4aff234542ea73546`, and reviewed on branch `review/astscope-94dae5` at `83912190b461a047cf59a8cfbdb788d9c5830857`. Origin: swift-atoms/swift-recursion `a454a8a6f9d5215e6f40ac64afa8a4bf29f2d643`, where `@Recursion` emits 14 derivation macros onto a nested enum (run 39540639205). Second consumer: swift-compositions/swift-sql `@Table` (`lane/swift-sql-issues-141`, run 39772176670). Ported to Issues on 27 Oct 2026.
