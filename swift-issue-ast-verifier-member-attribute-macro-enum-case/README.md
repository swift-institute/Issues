# Swift Issue: AST verifier "EnumCaseDecl should not have attributes" after a member-attribute macro annotates an enum case

**Upstream:** **NOT POSTED.** Same root cause as the open [swiftlang/swift#90139](https://github.com/swiftlang/swift/issues/90139) ("Member attribute macros apply extra attributes to each case element"). The record, [swift-institute/Issues#175](https://github.com/swift-institute/Issues/issues/175) (`upstream-candidate`), holds a drafted comment for #90139 that adds this abort, the one-file reproduction and the matrix. Posting needs Coen's explicit yes, and the record waits on [Issues#182](https://github.com/swift-institute/Issues/issues/182) (two-command reproductions) and a round-2 review.

**Classification:** compiler abort in the AST verifier. The source is valid. A member-attribute macro's attribute is attached to the `EnumCaseDecl` of an enum case, not only to its elements, and the verifier rejects it. Assertions builds run the verifier by default. Release toolchains skip it and accept the file, but abort the same way when it is turned on with `-Xfrontend -enable-ast-verifier`.

## Minimal reproducer

`Sources/Reproducer/Crash.swift.txt` (the lane's `final/case.swift`, kept in `evidence/lane/final/`) is one file with two roles. Built with `-D PLUGIN` it is a macro plugin that speaks the compiler's plugin protocol directly, so swift-syntax is not needed: `M` returns `@available(*, deprecated)` for every member. Built without the flag it is the client:

```swift
@attached(memberAttribute) macro M() = #externalMacro(module: "P", type: "M")

@M enum E { case a }
```

The record's commands (assertions builds):

```bash
swiftc -D PLUGIN repro.swift -o plugin
swiftc -load-plugin-executable plugin#P repro.swift
```

Any toolchain, including Xcode's release Swift:

```bash
swiftc -D PLUGIN repro.swift -o plugin
swiftc -typecheck -Xfrontend -enable-ast-verifier -load-plugin-executable plugin#P repro.swift
```

**Actual:**

```
EnumCaseDecl should not have attributes
Please submit a bug report (https://swift.org/contributing/#reporting-bugs) and include the crash backtrace.
```

The stack is `Verifier::walkToDeclPost` under `swift::verify(SourceFile&)` from `TypeCheckPrimaryFileRequest`. Exit 134 with `-typecheck`; the driver reports signal 6 without it.

**Expected:** the client type-checks. The attribute belongs on the case's elements, not on the `EnumCaseDecl`.

## Trigger characterization

From the lane (runs 39784950734 and 39786015934) and the round-1 review (39790509955 and 39794392449), on Windows 6.4.1, the Linux nightly and the macOS snapshots (`evidence/ci/`, variants in `evidence/review/`):

| Ingredient | Removed / replaced by | Result |
|---|---|---|
| a generated attribute | empty expansion (`v1_empty_expansion.swift`) | accepted |
| an enum case | `@M enum E {}` (`v4_no_case.swift`) | accepted |
| the macro | the attribute written by hand on the case (`v5_no_macro_attr_on_enum.swift`) | accepted |
| an enum | a struct member (`v6_struct_member.swift`) | accepted |
| `@available(*, deprecated)` | `@inline(never)`, a peer macro `@A`, `@MainActor` | still aborts (`@MainActor` is also diagnosed on release builds) |
| one attribute | two (swift-sql's `CaseCheck` and `ColumnCheck`) | still aborts |
| `case a` | `case a(Int)` | still aborts |
| `-typecheck` | a full compile | still aborts |
| the plugin's capability reply, `diagnostics` | removed | plugin protocol fails differently |

`-parse` accepts the file, since nothing is expanded.

## Toolchains

| Toolchain | Record's command | With `-Xfrontend -enable-ast-verifier` | Where |
|---|---|---|---|
| macOS main-snapshot-2026-10-17, Swift 6.5-dev (f62414fd1d17227), `+assertions` | aborts | not run | CI, run 39788628757 |
| macOS 6.4.x-snapshot-2026-10-20, Swift 6.4.4-dev (90b3468f3de7d1f), `+assertions` | aborts | not run | CI, run 39788628757 |
| Windows Swift 6.4.1 (swift-6.4.1-RELEASE), `+assertions` | aborts (exit 132) | not run | CI, run 39788628757 |
| Linux `swiftlang/swift:nightly-main-jammy`, Swift 6.5-dev, `+assertions` | aborts (exit 134) | not run | CI, run 39788628757 |
| macOS swift.org 6.4.1, Linux `swift:6.4.1-noble`, Xcode 26.6 (Swift 6.3.3) | accepted (no assertions) | not run | CI, run 39788628757 |
| Apple Swift 6.4.2 (swiftlang-6.4.2.1.9), Xcode, macOS arm64 | accepted | **aborts** | local, this port |

Run locally (`evidence/local-macos-6.4.2.txt`): the reproducer aborts with the verifier on, and the controls `v4_no_case`, `v6_struct_member` and `v1_empty_expansion` are accepted with the same flags. Not run locally: any assertions build, Linux, Windows. A Linux release toolchain with `-enable-ast-verifier` has not been tried anywhere.

## Workaround

None that keeps the macro's behaviour. In swift-sql the attributes are `@Table`'s compile-time payload checks (`CaseCheck`, `ColumnCheck`); not emitting them for enum cases removes the check. Release toolchains accept the code, so only assertions-build legs (the Windows leg in the fleet) fail.

## Harness

`Tests/Reproducer Tests.swift` and `Sources/Reproducer/main.swift` build the plugin and type-check the client in child processes with `-Xfrontend -enable-ast-verifier`, so the check runs on release toolchains too. The signature is `EnumCaseDecl should not have attributes`. A plugin that fails to build makes the probe inconclusive.

`withKnownIssue` uses `when: { knownToFire() }`: true on Darwin and on any assertions build (`swiftc --version` prints `+assertions`), the places the abort is recorded. On Issues CI that makes the macOS leg (Xcode) a live fix detector. A Linux release leg runs the body unguarded: if the abort fires there too, the test goes red and the predicate should be widened to include it, not replaced with `{ fired }`. The probes skip Windows, like the exemplar.

Checked locally (`evidence/local-macos-6.4.2.txt`): the test records the known issue and passes, and the probe exits 1. With `v4_no_case.swift` staged as `Crash.swift.txt` in a scratch copy, the test fails with "Known issue was not recorded" and the probe exits 0.

## Provenance

Reduced on 22 Oct 2026 on the private repository `swift-institute/windows-exception-29-reproducer`, branch `lane/astscope-member-attribute` at `0f646c6a6a605a799991e7a4aff234542ea73546` (`final/case.swift`), and reviewed on branch `review/enumcase-a1effe` at `14c3d7ea6b6ee32b283d06e483b279839f22471e`. Origin: swift-compositions/swift-sql `lane/swift-sql-issues-141` at `afd3b682d51057c6234c8f0034a87507b1439a6c`, run 39772176670 (Windows release, `enum Attachment` in `Enum Table Tests.swift:12`). The same run also hit the ASTScope abort of `swift-issue-astscope-member-attribute-macro-overlapping-scopes`. Ported to Issues on 27 Oct 2026.
