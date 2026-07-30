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

## Re-verification (2026-07-30) — does not reproduce on current toolchains

The retained reproducer (`evidence/source/Crash.swift.txt`, staged as
`Crash.swift`) was recompiled with the source-reported command,
`swiftc -parse-as-library -emit-ir Crash.swift`, each row
`swift --version`-confirmed on the arm64 macOS host:

| Toolchain | Result |
|---|---|
| 6.3.3-RELEASE | exit 0, clean |
| Apple Swift 6.4 (Xcode) | exit 0, clean |
| 6.4.x-snapshot-2026-07-23 (+assertions) | exit 0, clean |
| main-snapshot-2026-07-11 (+assertions) | exit 0, clean |

The file compiles as retained — the reconstruction itself succeeded; the
signal-11 `swift::irgen::emitAsyncReturn` crash reported on Swift 6.2.3 is
simply gone, fixed somewhere between 6.2.3 and 6.3.3-RELEASE.

**Eligibility statement:** nothing to file upstream — the defect is absent
from every currently supported toolchain line, so no upstream issue would be
actionable. No reproducer target is added; this directory remains a closed
evidence record. The overlap noted in Batch F with the linked typed-throws
reproducers is moot for the same reason: this trigger family
(async + typed throws + generic-nested error) no longer fails anywhere it
was probed.
