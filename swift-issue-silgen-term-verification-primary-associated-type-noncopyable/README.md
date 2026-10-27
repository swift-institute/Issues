# Swift Issue: requirement-machine "Term verification failed" in SILGen for an initializer pinning a `~Copyable` parameter to a nested conditional conformer

**Upstream:** [swiftlang/swift#93525](https://github.com/swiftlang/swift/issues/93525) (open). Filed on 21 Oct 2026 by the coordinator without Coen's agreement; Coen ruled on 22 Oct that it stays open. Nothing more to file.

**Local tracking:** [swift-institute/Issues#113](https://github.com/swift-institute/Issues/issues/113), the "swift-coder locus" cluster (`Coder.Case+Operation.swift:72`). Not #133: that record is an IRGen segfault in `emitOpaqueTypeDecl` on Xcode beta, a different crash.

**Classification:** compiler abort in an assertions-only check. An assertions-enabled `swift-frontend` aborts in `RequirementMachine::verify` while SILGen lowers the initializer. `-typecheck` succeeds. Release toolchains (Xcode, swift.org releases) do not run this check and compile the file.

## Minimal reproducer

`Sources/Reproducer/Crash.swift.txt` (32 lines; the lane's `v3/m11_primary_on_coding.swift`, kept as `evidence/v3/`):

```swift
protocol Parsing: ~Copyable {
    associatedtype Input: ~Copyable
    associatedtype Output: ~Copyable
}
protocol Coding<Input, Output>: Parsing, ~Copyable where Input: ~Copyable, Output: ~Copyable {}
protocol Symbol { associatedtype Input: ~Copyable }
struct App<Index: Symbol, Input: ~Copyable>: ~Copyable where Index.Input == Input {}
extension App where Input: ~Copyable {
    struct Coder<Inner: Coding>
    where Inner.Input: ~Copyable, Inner.Output: ~Copyable, Inner.Output == Input {}
}
// … conditional conformances of App.Coder to Parsing and Coding, then:
struct Case<Input: ~Copyable, Source: ~Copyable, Focus: ~Copyable, Content: Coding & ~Copyable>: ~Copyable
where Content.Input == Input, Content.Output == Focus {}
extension Case where Input: ~Copyable, Source: ~Copyable, Focus: ~Copyable {
    init<Index: Symbol, Inner: Coding>(dummy: Void)
    where
        Focus == App<Index, Index.Input>,
        Content == App<Index, Index.Input>.Coder<Inner>,
        // …
    { fatalError() }
}
```

```bash
swiftc -c -parse-as-library Crash.swift -o Crash.o
```

**Actual (assertions builds):**

```
Abort: function verify at GenericSignatureQueries.cpp:880
Term verification failed
Initial term:    τ_0_3.[Parsing:Input]
Erased term:     τ_0_3.Input
Simplified term: τ_0_3.Input
```

Exit 134 on Linux, `-1073741795` (0xC000001D, "exception 29") on Windows.

**Expected:** the file compiles, as it does on release toolchains.

## Trigger characterization

From the lane's matrix on Windows 6.4.1 with assertions and the Linux nightly (each row differs from the crashing file by one thing; files in `evidence/v3/`):

| Variant | Result |
|---|---|
| `m11_primary_on_coding.swift` (the reproducer) | aborts |
| `z1_only_copyable_inverse.swift` (fuller mimic: Serializing, Buffer, Failure, no `~Escapable`) | aborts |
| `m12_primary_on_parsing.swift`: primary associated types on `Parsing` instead of `Coding` | compiles |
| `m13_no_primary.swift`: no primary associated types on `Coding` | compiles |
| `p1_case_content_parsing_only.swift`: `Case.Content: Parsing` instead of `Coding` | compiles |
| `q1_z1_case_parsing_serializing.swift`: `Content: Parsing & Serializing` | compiles |
| `y1_no_inverses.swift`: no `~Copyable` anywhere | compiles |

The lane also found that the body, the restated `Inner.Input == Input`, the `Focus ==` line, the nesting, parameter names and requirement order do not matter. Details are on Issues#113.

## Toolchains

| Toolchain | Result | Where |
|---|---|---|
| Windows Swift 6.4.1 (swift-6.4.1-RELEASE), `Build config: +assertions` | aborts | CI, runs 39642339405 and 39643341814 (`evidence/ci/`) |
| Linux `swiftlang/swift:nightly-main-jammy`, Swift 6.5-dev (f62414fd1d17227), `+assertions` | aborts (`-c` and `-emit-silgen`; `-typecheck` passes) | CI, runs 39643341814 and 39649025095 |
| Apple Swift 6.4.2 (swiftlang-6.4.2.1.9), Xcode, macOS arm64, no assertions | compiles | local, this port (`evidence/local-macos-6.4.2.txt`) |

**Not run locally.** This Mac has only Xcode's Swift 6.4.2, which has no assertions, so the bug cannot fire here. The local run shows the crash file and the controls compile, which is expected and proves nothing about the bug. The firing evidence is CI only. A Windows main snapshot could not be measured: `swift-frontend.exe` from `swift-DEVELOPMENT-SNAPSHOT-2026-10-17-a` does not start on `windows-latest` (see the growth-policy evidence of `swift-issue-irgen-nonthrowing-typed-throws-closure-crash`).

## Workaround

None that keeps the API. The only passing shapes drop the primary associated types from `Coding` or drop `Coding` from the `Case` requirement. The second was tried on swift-coder and rejected by Coen on 21 Oct. The 11 repositories that depend on swift-coder stay red on the Windows leg until a toolchain fix.

## Harness

`Tests/Reproducer Tests.swift` and `Sources/Reproducer/main.swift` compile `Crash.swift.txt` with `swiftc -c -parse-as-library` in a child process, since the file aborts the compiler. The signature is `Term verification failed`.

The bug fires only on assertions builds, so `withKnownIssue` uses `when: { assertionsToolchain() }`, which is true when `swiftc --version` prints `+assertions`. On an assertions toolchain the test is green while the abort fires and turns red once the file compiles. On a release toolchain the body runs unguarded and passes. `main.swift` exits 1 when the abort fires and 0 otherwise; on a release toolchain it says the result is inconclusive.

Like the exemplar, the probes run only where `/usr/bin/env swiftc` exists (macOS, Linux). They skip Windows. The Issues CI legs that run tests are macOS (Xcode) and Linux release, both without assertions, plus Windows 6.4 with assertions, where these probes skip. So on current Issues CI this harness never sees the bug fire.

How the harness was checked locally (`evidence/local-macos-6.4.2.txt`): on Xcode 6.4.2 the test passes and the probe exits 0 (inconclusive). A stand-in `swiftc` that reports `+assertions` and replays the abort text recorded on CI (`evidence/stub/`) makes the test record the known issue and the probe exit 1. The same stand-in exiting 0 makes the test fail with "Known issue was not recorded" and the probe exit 0. The stand-in compiles nothing; it only shows the harness reads both outcomes.

## Provenance

Reduced on 21 Oct 2026 on the private repository `swift-institute/windows-exception-29-reproducer`, branch `main`. The `v3/` files last changed at `133e228082b60f1f63d8e79a79ad1d398561e9bf` ("Keep the 40-line swift-coder reduction with its controls"). They are copied from `main` at `7ad41ef5b24d08db52ede2c97b4fccdc3753dc04`, with `run.sh` and the `repro`, `nightly` and `linux-detail` workflows. Origin: swift-atoms/swift-coder `Coder.Case+Operation.swift:72`, job 118964762335, run 39520941987, head `bef97390670fe08fcc812d3bca61c811543936bf`. Ported to Issues on 27 Oct 2026.
