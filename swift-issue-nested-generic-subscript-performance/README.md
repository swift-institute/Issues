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

## Closed as not a defect (2026-10-11)

Upstream swiftlang/swift#86666 was closed on 2026-05-06 by the reporter. A reviewer pointed out that unspecialized generic code is slower in general. The `-O` measurements then showed parity on 6.2.3 and 6.3.1 (1.00x), so the gap is `-Onone` code-generation cost and not an optimizer defect. On Apple Swift 6.4 (swiftlang-6.4.0.34.1) the slowdown at `-Onone` remains, as expected for debug builds.

A fresh `-O` measurement on 2026-10-11 was not usable. The machine was under load: two runs of the same binary gave different ratios (nested 1.9x vs 2.2x, flat `_read` 1.4x vs 0.9x), and the `-Onone` run did not finish within the 90-second bound. The closing conclusion rests on the May measurements. Re-measure on a quiet machine if optimized-build parity is ever in doubt.
