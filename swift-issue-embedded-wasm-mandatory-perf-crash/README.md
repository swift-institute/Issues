# `swift-issue-embedded-wasm-mandatory-perf-crash`

`swift-frontend` crashes (signal 11) compiling a **consumer** module under
the Swift 6.3.x **wasm32 Embedded** SDK when that module calls the
cross-Tagged arithmetic operator
`Index<T>.zero + Index<T>.Count.zero -> Index<T>` from
`swift-index-primitives`:

```
Assertion failed: (ty->isLegalSILType() && "constructing SILType with type
that should have been " "eliminated by SIL lowering"), function SILType at SILType.h:115.
While evaluating request ExecuteSILPipelineRequest(Run pipelines
  { Mandatory Diagnostic Passes + Enabling Optimization Passes } on SIL …)
While running pass … SILModuleTransform "MandatoryPerformanceOptimizations".
#10 swift::eliminateDeadAllocations(swift::SILFunction*, swift::DominanceInfo*)
```

## Observed / expected

- **Observed**: signal 11 in `MandatoryPerformanceOptimizations`
  (sub-pass `eliminateDeadAllocations`) while compiling the consumer module
  for `wasm32-unknown-wasip1` Embedded on Swift 6.3.2-RELEASE.
- **Expected**: successful compilation — the same code compiles cleanly on
  every non-Embedded target and on 6.4-dev nightly Embedded (Linux).

## Minimal reproduction (verified)

Two live lines of consumer code (`Sources/Reproducer/Crash.swift.txt`):

```swift
public import Index_Primitives

public let x: Index<Int> = .zero + .zero
```

wrapped in a SwiftPM package whose single `Consumer` target depends on the
`Index Primitives` product of
`https://github.com/swift-primitives/swift-index-primitives.git`
(branch `main`) — the manifest is background provenance, reproduced in full
in the git history of this entry's `Crash.swift.txt`. The verified container
invocation, exactly as recorded:

```sh
docker run --name r -d -v $PWD:/work -w /work swift:6.3.2-jammy sleep infinity
docker exec r swift sdk install \
  "https://download.swift.org/swift-6.3.2-release/wasm-sdk/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE_wasm.artifactbundle.tar.gz" \
  --checksum "a61f0584c93283589f8b2f42db05c1f9a182b506c2957271402992655591dd7c"
docker exec r swift build --swift-sdk swift-6.3.2-RELEASE_wasm-embedded
```

Expected: signal 11 during `MandatoryPerformanceOptimizations` on the
Consumer module's SIL.

**Reduction limit (recorded)**: the production dependency chain is
load-bearing. Single-file `swiftc -wmo -enable-experimental-feature Embedded`
with inlined equivalents, a structurally-equivalent 2-module SwiftPM split,
and 5-module synthetic chains (including full `~Copyable & ~Escapable` and
production feature flags) all failed to reproduce — see
[INVESTIGATION-ARC.md](INVESTIGATION-ARC.md) for the phase-by-phase log.

## Affected Swift versions

| Target | Compiler | Result |
|---|---|---|
| macOS arm64, Linux x86_64 (debug/release, non-Embedded) | 6.3.2-RELEASE | clean |
| Linux x86_64 Embedded | 6.4-dev nightly | clean (**fixed**) |
| `wasm32-unknown-wasip1` Embedded (wasm SDK) | 6.3.2-RELEASE | **CRASH** |

Fixed on 6.4-dev; only the 6.3.x wasm-embedded configuration reproduces.

## Harness

The Embedded/Wasm configuration cannot run in this repository's
dependency-free local lane, so this entry's targets are honest stubs: the
`…-Repro` executable compiles on host and exits 2 (inconclusive) with the
documented reproduction printed; the `…-Tests` target checks fixture
integrity only (the trigger file is present with its two live lines). The
reproduction of record is the container invocation above.

## Upstream

**Destination**: `swiftlang/swift`.
**Search (2026-07-30)**: `eliminateDeadAllocations` in issues — no matching
report; `"isLegalSILType"` — closest is
[swiftlang/swift#78439](https://github.com/swiftlang/swift/issues/78439)
(open; the same `constructing SILType with type that should have been
eliminated by SIL lowering` assertion, but in SendNonSendable, not
Embedded/MandatoryPerformanceOptimizations — distinct trigger).
**Searched, no match — status: fixed on 6.4-dev, so a new filing would be a
6.3.x backport request**, appropriate while the stable Wasm SDK ships
against 6.3.x. Filing remains principal-gated.

## Workaround

Consumer-side `#if !hasFeature(Embedded)` guard around code paths invoking
the operator across the module boundary (applied to the surfacing package's
test-support inits). No source-level workaround exists in the upstream
operator itself — removal of `@inlinable`, `@_optimize(none)`, and body
restructuring were all verified NOT to help; only a semantics-breaking no-op
body compiles. Remove the guards when the Wasm SDK ships against Swift 6.4+.

## Provenance (Institute discovery context)

Surfaced 2026-05-18 by `swift-primitives/swift-vector-primitives` CI (run
`26057005651`, job `76607485580`, commit `894098d`) building
`Vector_Primitives_Test_Support` for wasm32 Embedded. Reduced in Docker from
the ~50-line production shape to the two-line consumer above; the bug lives
in `swift-index-primitives`' dep chain, not `swift-vector-primitives`. Full
reduction log, ingredient verification, and failed-workaround table:
[INVESTIGATION-ARC.md](INVESTIGATION-ARC.md).
