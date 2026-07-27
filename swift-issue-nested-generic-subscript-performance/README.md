# `[Compiler][Performance] nested value-generic subscript remains slower in unoptimized builds`

Canonical work item: [swift-institute/Issues#10](https://github.com/swift-institute/Issues/issues/10)

Canonical evidence path: [swift-issue-nested-generic-subscript-performance](https://github.com/swift-institute/Issues/tree/main/swift-issue-nested-generic-subscript-performance)

This directory is runnable benchmark and SIL evidence for the canonical GitHub Issue.

Nested generic `InlineArray` subscript access has source-recorded overhead at `-Onone` and specializes to parity at `-O`. Correctness is not at issue; this distinguishes debug code-generation cost from optimized production behavior.

Run the benchmark through the workspace build coordinator in debug and release configurations. The source’s original commands were:

```console
swift run -c debug Benchmark
swift run -c release Benchmark
```

`SIL.md` retains the source-recorded optimized structural comparison. No fresh benchmark or compiler result is included in this staging packet.

Source-reported environment: Apple Swift 6.2.3 and 6.3.1 on M-series macOS. Upstream: [swiftlang/swift#86666](https://github.com/swiftlang/swift/issues/86666) (resolved). Privacy screen: `PUBLIC_SAFE`.
