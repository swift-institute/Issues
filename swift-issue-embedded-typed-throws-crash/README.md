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

## Re-verification (2026-07-30) — does not reproduce on current toolchains

The retained source (`evidence/source/TypedThrowsCrash.swift.txt`, staged as
`TypedThrowsCrash.swift`) was recompiled with bare `swiftc`, each row
`swift --version`-confirmed:

| Invocation | Toolchain | Result |
|---|---|---|
| `swiftc -enable-experimental-feature Embedded -enable-experimental-feature Lifetimes -wmo -c` (host arm64) | 6.3.3-RELEASE | exit 0, clean |
| same host-embedded invocation | main-snapshot-2026-07-11 (+assertions) | exit 0, clean |
| `swiftc -target wasm32-unknown-wasip1 -enable-experimental-feature Embedded -enable-experimental-feature Lifetimes -wmo -sdk <WASI.sdk> -resource-dir <embedded swift resources> -c` (swift-6.3.3-RELEASE wasm SDK bundle) | 6.3.3-RELEASE | exit 0, clean |

The wasm32 row exercises the same Embedded configuration class the source
report named (`swift build --swift-sdk swift-6.2.3-RELEASE_wasm-embedded`),
through bare `swiftc` against the SDK bundle's WASI sysroot and embedded Swift
resources. `MandatoryPerformanceOptimizations` runs in every Embedded-mode
compile, including the passing host rows.

**Eligibility statement:** the crash was reported on Swift 6.2.3 and does not
reproduce on 6.3.3-RELEASE or a 6.5-dev main snapshot in either the host or
wasm32 Embedded configuration. There is nothing to file upstream: the defect
is absent from every currently supported toolchain line. No reproducer target
is added; this directory remains a closed evidence record, and the only event
that would reopen it is the signature reappearing on a current toolchain.
