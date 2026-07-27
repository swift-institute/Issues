# `[Compiler][ICE] Embedded Swift typed throws on protocol conformances crash compilation`

Canonical work item: [swift-institute/Issues#5](https://github.com/swift-institute/Issues/issues/5)

Canonical evidence path: [swift-issue-embedded-typed-throws-crash](https://github.com/swift-institute/Issues/tree/main/swift-issue-embedded-typed-throws-crash)

This directory is evidence for the canonical GitHub Issue, not a second status ledger.

## Summary

The source report records an Embedded Swift compiler crash for typed-throws protocol conformances. Correct behavior is successful compilation for the configured Embedded target or a source diagnostic.

The source names `swift build --swift-sdk swift-6.2.3-RELEASE_wasm-embedded` and a signal-5 failure in `MandatoryPerformanceOptimizations`. The exact SDK/toolchain and signature have not been freshly recaptured, so this staging packet asserts no new result.

To avoid accidental compilation on an unsuitable host lane, the manifest and source are retained byte-for-byte as `.txt` resources under `evidence/source/`. Reconstruct the original names only in an isolated Embedded verification workspace.

Workaround: avoid this typed-throws conformance shape until a failing/fixed matrix is verified.

Upstream: not filed. Privacy screen: `PUBLIC_SAFE`.
