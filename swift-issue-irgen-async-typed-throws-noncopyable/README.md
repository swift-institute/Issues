# `[Compiler][ICE] async typed throws with a nested generic error crashes IRGen`

Canonical work item: [swift-institute/Issues#8](https://github.com/swift-institute/Issues/issues/8)

Canonical evidence path: [swift-issue-irgen-async-typed-throws-noncopyable](https://github.com/swift-institute/Issues/tree/main/swift-issue-irgen-async-typed-throws-noncopyable)

This directory is forensic evidence for the canonical GitHub Issue.

An async function using a nested error type inside a generic container is expected to emit IR. The source report records signal 11 in `swift::irgen::emitAsyncReturn` on Swift 6.2.3 arm64 macOS 26.

The four-line reproducer is retained byte-for-byte as `evidence/source/Crash.swift.txt`; it is intentionally not a compilable dossier target because direct compilation is the compiler-crash trigger. In an isolated verification lane, restore the `.swift` suffix and use the source-reported command:

```console
swiftc -parse-as-library -emit-ir Crash.swift
```

No fresh run or result is included. Workaround: hoist the error type out of the generic container. Upstream: not filed; #77297 and #83011 are related. Privacy screen: `PUBLIC_SAFE`.
