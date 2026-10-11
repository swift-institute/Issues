# Draft for swiftlang/swift (not filed)

Status: not to be filed. Coen ruled on 2026-10-11 that there are no new upstream filings; this record in swift-institute/Issues is the report. The text below is kept for reference.

Duplicate search (2026-10-11) of swiftlang/swift for "_rawLayout", "rawLayout Instruction does not dominate" and "rawLayout likeArrayOf release crash": no report of this crash on its own. It was described in comments on swiftlang/swift#86652, but that issue was closed for the separate cross-module deinit bug (runtime fix #89809), and this crash remains.

---

**Title:** `-O` LLVM verifier abort: generic `@_rawLayout(likeArrayOf:)` field followed by another field in a type with deinit

### Description

A `~Copyable` type stores a generic-element `@_rawLayout(likeArrayOf: T, count: n)` value, then another stored property, and has a `deinit`. Compiling with `-O` aborts in LLVM's module verifier: the element stride used to compute the trailing field's offset is loaded inside the per-element destroy loop, but used after it, on a path that skips the loop.

### Reproduction

```swift
@_rawLayout(likeArrayOf: T, count: 2)
struct Raw<T>: ~Copyable { init() {} }

struct S<T>: ~Copyable {
    var raw: Raw<T>
    var x: Int
    init() { raw = Raw(); x = 0 }
    deinit {}
}
```

```
$ swiftc -swift-version 6 -parse-as-library -enable-experimental-feature RawLayout -O -c Repro.swift
Instruction does not dominate all uses!
  %14 = load i64, ptr %13, align 8, !invariant.load !17
  %23 = mul i64 %14, 2
<unknown>:0: error: fatal error encountered during compilation; please submit a bug report (https://swift.org/contributing/#reporting-bugs)
<unknown>:0: note: Broken module found, compilation aborted!
```

Each of these compiles: declaring `x` before `raw`, removing the `deinit`, using `@_rawLayout(like: T)` instead of `likeArrayOf`, or using a concrete element type with a generic count. `-Onone` compiles.

### Expected behavior

The module verifies and compiles at `-O`.

### Environment

- Apple Swift 6.4 (swiftlang-6.4.0.34.1), arm64-apple-macosx27.2.0
- Also reproduces on swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a and swift-DEVELOPMENT-SNAPSHOT-2026-07-11-a (6.5-dev)
- Earlier records: 6.3.1 and 6.4-dev on Linux aarch64
