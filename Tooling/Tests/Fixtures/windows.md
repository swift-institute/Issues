### Owner

swiftlang/swift (compiler, standard library, runtime, SourceKit)

### Why this owner

Fixture: a Windows-only record, for the readiness tests. `swift-frontend` aborts in ASTScope verification on the swift.org Windows x86_64 toolchains (an assertions build) with a one-file reproduction that imports nothing; the macOS toolchains compile it.

### Upstream action

New issue

### Crash signature

```text
crashed: yes
phase: Abort: function abortWithVerificationError
requires: child overlaps previous child
```

Taken on windows-6.4.1. Windows toolchains print unsymbolized frames, so the verifier's own text identifies the crash.

### Toolchain matrix

| Toolchain | `swiftc --version` | Result |
|---|---|---|
| windows-6.4.1 | Swift version 6.4.1 (swift-6.4.1-RELEASE) | reproduces |
| windows-6.4.x-snapshot-2026-10-17 | Swift version 6.4.4-dev (LLVM 0000000, Swift 0000000) | reproduces |
| windows-main-snapshot-2026-10-17 | Swift version 6.5-dev (LLVM 0000000, Swift 0000000) | reproduces |
| 6.4.1 | Apple Swift version 6.4.1 (swift-6.4.1-RELEASE) | does not reproduce |
| main-snapshot-2026-10-17 | Apple Swift version 6.5-dev (LLVM 0000000, Swift 0000000) | does not reproduce |

### Regression range

_No response_

### Duplicate search

Run 2026-10-22 against swiftlang/swift:

```sh
gh search issues "child overlaps previous child" --repo swiftlang/swift
gh search prs "abortWithVerificationError" --repo swiftlang/swift
```

Verdict: no duplicate.

### Minimal reproduction

```swift
enum E { case a }
```

```sh
swiftc -parse-as-library -c repro.swift
```

### Reproduces on

windows-6.4.1

### Reduction record

`issue-reduce` on the Windows runner reached a fixed point.

Independent review: reproduced from the draft alone on windows-6.4.1; nothing left to remove.

### Upstream draft

#### Description

The Windows assertions toolchain aborts in ASTScope verification.

#### Reproduction

```swift
enum E { case a }
```

```sh
swiftc -parse-as-library -c repro.swift
```

#### Stack dump

```text
child overlaps previous child
Abort: function abortWithVerificationError at ASTScopePrinting.cpp:78
```

#### Expected behavior

It compiles.

#### Environment

Windows x86_64, Swift 6.4.1 (`6.4.1+Asserts`).

#### Additional information

None.

### Readiness

- [X] The reproduction is one file and one command, and uses no Institute code or third-party package.
- [X] The matrix was run with the minimal reproduction, on toolchains installed from swift.org or the stated Xcode.
- [X] The duplicate search covered open and closed issues and pull requests in the owner's repository.
- [X] An independent reviewer reproduced it from the draft alone and found nothing left to remove.

### Filing record

_No response_
