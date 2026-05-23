---
title: "swiftlang/swift — Tagged + Atomic + `~Copyable` cross-module conditional-conformance runtime metadata SIGSEGV"
status: PENDING-ORCHESTRATOR-AUTHORIZATION
date: 2026-05-23
filing-target: swiftlang/swift
filing-posture: backport-request (fixed on 6.5-dev nightly; broken on Apple Swift 6.3.2 Xcode 26.4.1)
classification: Runtime crash / miscompile (per [ISSUE-010])
---

> **STATUS** (2026-05-23): pending orchestrator authorization per
> [`ISSUE-008`]. The bug is fixed on Swift 6.5-dev nightly
> `2026-03-16-a` (and every nightly we sampled afterward), so a new bug
> report against `main` is not warranted; the appropriate ask is a
> 6.3.x backport request OR a paper trail referencing the historical
> failure for future ecosystem readers.

# Swift Bug Report: Tagged + Atomic + `~Copyable` Runtime Metadata SIGSEGV

## Title

> [SIL/Runtime] `__swift_instantiateConcreteTypeFromMangledNameV2` returns null
> on cross-module conditional `AtomicRepresentable` conformance with `~Copyable`
> Tag suppression — `Atomic<Tagged<Tag, Ordinal>>.advance(within:)` SIGSEGVs at
> `address=0x10` on Apple Swift 6.3.x; fixed on Swift 6.5-dev.

## Environment

- **Toolchain (broken)**: Apple Swift 6.3.2 RELEASE
  (`swiftlang-6.3.2.1.108 clang-2100.1.1.101`), Xcode 26.4.1
- **Toolchain (fixed)**: Swift 6.5-dev nightly `2026-03-16-a` /
  `2026-05-07-a` / `2026-05-12-a` (`org.swift.64202603161a` and later)
- **Platform**: macOS 26.2 (build 25C56), arm64. Linux not yet verified
  on this specific shape but the crash signature involves runtime
  metadata lookup, which is cross-platform; Linux 6.3.x is likely
  affected identically.
- **Build configuration**: both debug (`-Onone`) and release (`-O`)
  reproduce on 6.3.2. Both pass on 6.5-dev.
- **SwiftPM context**: the reproducer requires SwiftPM with three
  external `swift-primitives` dependencies. Bare-`swiftc` reduction is
  not achievable for this defect class — see
  [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) Arc 4 §`[ISSUE-002]`
  Bare-`swiftc` reduction attempted; not achievable, for the
  empirically refuted local-copy variants (single-file, 2-module,
  3-module with retroactive conformance, 4-module split with generic
  Atomic extension — all PASS on 6.3.2).

## Reproducer

`swift-institute/Issues/swift-issue-tagged-noncopyable-atomic-metadata-crash/Sources/Reproducer/main.swift`:

```swift
import Synchronization
import Tagged_Primitives
import Ordinal_Primitives
import Cardinal_Primitives

private enum SimpleTag: Sendable {}

let cursor = Atomic<Tagged<SimpleTag, Ordinal>>(.zero)
let count: Tagged<SimpleTag, Cardinal> = try! .init(2)
let result = cursor.advance(within: count)
print("result = \(result.underlying.rawValue)")
```

`Package.swift` declares three external dependencies on:

- `https://github.com/swift-primitives/swift-tagged-primitives.git` — defines `Tagged<Tag, Underlying>`
- `https://github.com/swift-primitives/swift-ordinal-primitives.git` — defines `Ordinal` and the `.advance(within:)` extension on `Atomic`
- `https://github.com/swift-primitives/swift-cardinal-primitives.git` — defines `Cardinal` (the `within:` parameter type)

The Tagged conformance to `AtomicRepresentable` lives in a sibling
SwiftPM target of `swift-tagged-primitives`:
`Tagged Primitives Standard Library Integration`, declared as:

```swift
extension Tagged: AtomicRepresentable
where Underlying: AtomicRepresentable, Tag: ~Copyable {
    public typealias AtomicRepresentation = Underlying.AtomicRepresentation
    // ...
}
```

## Steps to reproduce

```bash
git clone https://github.com/swift-institute/Issues
cd Issues
swift run swift-issue-tagged-noncopyable-atomic-metadata-crash-Repro
```

- On Apple Swift 6.3.x: process killed by SIGSEGV; exit 139.
- On Swift 6.5-dev nightly `2026-03-16-a` and later: prints `result = 0`; exit 0.

## Observed behavior

```
EXC_BAD_ACCESS (code=1, address=0x10)
Frame: Atomic<Tagged_Primitives.Tagged<Tag, Ordinal_Primitive.Ordinal>>.advance(within:)+92
```

Stack trace (verified via lldb on the prior arc's standalone
reproducer, 2026-05-22):

```
sigsegv-repro` Atomic<Tagged<…, Ordinal>>.advance(within:) + 92  ← faulting instruction: ldr x2, [x1, #0x10]
  ← x1 is null (loaded from __swift_instantiateConcreteTypeFromMangledNameV2's stored result)

The null came from:
  sigsegv-repro` __swift_instantiateConcreteTypeFromMangledNameV2
    → bl libswiftCore.dylib` swift_getTypeByMangledNameInContext2
    → b  libswiftCore.dylib` swift_getTypeByMangledNameInContextImpl
    → bl libswiftCore.dylib` swift_getTypeByMangledName
       → returns TypeLookupErrorOr{ tag = 1 (error),
                                    invoke vtable = &TypeLookupError::TypeLookupError(char const*)::__invoke,
                                    message = "unknown error" }
```

When `SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1` is set, stderr precedes the
SIGSEGV with:

```
failed type lookup for <symbolic-mangled-name-bytes>: unknown error
```

## Expected behavior

The runtime should resolve the mangled name to the conformance
descriptor that IS present in the binary at the offset corresponding to
the conformance symbol
`_$s17Tagged_Primitives0A0Vyxq_G15Synchronization19AtomicRepresentable0a1_B29_Standard_Library_IntegrationAeFR_Ri_zrlMc`,
producing a valid metadata pointer. The Swift 6.5-dev nightly does
exactly this — the demangler resolves the inline-name fragment +
back-references correctly and the call returns cleanly.

## Failing mangled-name fragment

Symbolic mangled name decoded byte-for-byte (per the prior arc's lldb
walk, 2026-05-22):

```
0x02 65 c8 00 00   indirect-symref → Synchronization.Atomic
'y'                generic args open
0x02 2f bb 00 00   indirect-symref → Tagged_Primitives.Tagged
'y'                generic args open (for Tagged)
0x01 dd 58 00 00   DIRECT-symref   → consumer.SimpleTag
0x02 1c bb 00 00   indirect-symref → Ordinal_Primitive.Ordinal
"GAE"              close-generic, ?, then E (constrained-extension marker)
0x02 1c c8 00 00   indirect-symref → ???
"46Tagged_Primitives_Standard_Library_Integration"     ← 46-char INLINE module identifier
"_AdF08Ordinal_b1_c1_d1_E0yHCHCg_G"                    ← back-reference trailer
0x00               terminator
...
```

The 46-character inline-encoded identifier
`Tagged_Primitives_Standard_Library_Integration` is the sibling
SwiftPM target where the conformance is defined. The compiler emits
this as an inline name lookup (not a 5-byte symbolic reference) because
the conformance lives in a different module than the consumer's call
site and requires demangling-time path resolution. The back-references
(`b1`, `c1`, `d1`) point to earlier substitution slots; `yHCHCg`
denotes a Sendable-conformance witness marker.

## Investigation summary

This reproducer was reduced across three investigation arcs and four
empirical findings:

1. **The bug is specific to `Tagged_Primitives.Tagged`**: a local
   wrapper struct mirroring Tagged's exact declaration shape
   (`~Copyable & ~Escapable`, conditional Copyable/Escapable/Sendable/
   BitwiseCopyable/AtomicRepresentable conformances) does NOT
   reproduce. Bare-`swiftc` reduction attempts at 1-file, 2-module,
   3-module retroactive-conformance, and 4-module split-conformance
   shapes all PASS on 6.3.2.
2. **The trigger is not a single-file edit to `Tagged.swift`**: a
   nine-candidate single-file bisection (removing `@frozen`, dropping
   `package(set)`, dropping struct-level `~Escapable`, removing all six
   optional stdlib conformances, hoisting `AtomicRepresentable`
   conformance from SLI into the main module, removing the `modify`
   extension) failed to fix the crash on any candidate.
3. **The `Tag: ~Copyable` suppression on the conformance is not the
   trigger**: dropping the `Tag: ~Copyable` clause from
   `extension Tagged: AtomicRepresentable` had no effect.
4. **Only the generic extension method `.advance(within:)` crashes**:
   `Atomic<Tagged<…>>.load(ordering:)` PASSES; only the generic
   `.advance(within:)` extension (which has where-clauses
   `Value: Ordinal.\`Protocol\` & AtomicRepresentable`,
   `Value.AtomicRepresentation == UInt.AtomicRepresentation`, plus
   `C: Carrier.\`Protocol\`<Cardinal>` and `Value.Domain == C.Domain`)
   triggers the demangling-time lookup that fails.

The runtime location of the failure is identifiable but not actionable
from outside the compiler:
`stdlib/public/runtime/MetadataLookup.cpp`,
`swift_getTypeByMangledName` (or one of its early-pipeline callees)
constructs a default `TypeLookupError("unknown error")` before reaching
any of the high-level entry points
(`swift_getCanonicalSpecializedMetadata`,
`swift_lookUpProtocolConformance`,
`swift_getAssociatedTypeWitness`,
`swift_getOpaqueTypeMetadata`,
`swift_getExtendedExistentialTypeMetadata`,
`swift::ResolveAsSymbolicReference::operator()`). None of those are
called — the error is constructed in the demangling-and-tokenization
stage before any of them dispatch.

## Related upstream issues

Searched `gh search issues 'swift_getTypeByMangledName'`,
`'instantiateConcreteTypeFromMangledName'`,
`'AtomicRepresentable conditional conformance'`,
`'TypeLookupError unknown error'`:

- [`#74303`](https://github.com/swiftlang/swift/issues/74303) — DiscordBM
  `IntBitField<DiscordApplication.Flag>?` Codable+Optional bitfield. OPEN.
  Same failure family (`__swift_instantiateConcreteTypeFromMangledName`
  null return), different domain. Closed dupe `#74333`.
- [`#69615`](https://github.com/swiftlang/swift/issues/69615) — Kubrick
  `@JobBuilder buildBlock` opaque-return-type metadata
  (`getTypeByMangledNameInContext` TypeLookupError). OPEN. Same family,
  different domain.

No exact-shape duplicate for cross-module conditional
`AtomicRepresentable` conformance with `~Copyable` Tag suppression. If
upstream wants a separate issue rather than rolling our shape into
`#74303` or `#69615`, we can file. If they prefer consolidation, this
draft can be added as a comment on `#74303`.

## Asks

1. Confirm whether the fix that landed in the 6.4-dev → 6.5-dev
   nightly stream (somewhere between 6.3.2's release and
   `2026-03-16-a`) was an intentional fix for a tracked issue or a
   collateral fix from another runtime / demangler change. If
   intentional: which commit / which tracked issue?
2. If a 6.3.x backport is feasible: please backport. The bug currently
   blocks `swift test` in three swift-foundations packages
   (`swift-executors`, `swift-threads`, `swift-io`) on Apple Swift
   6.3.2 (the current Xcode default), with no Institute-side
   workaround that preserves the typed phantom-Tag storage.
3. If a backport is not feasible: confirmation is enough — we'll wait
   for the Swift 6.5 release and the test runs will pass.

## Workaround status

Per [`ISSUE-008`] the "Fixed on dev toolchain, not in Xcode" path
recommends applying and documenting a workaround. The
typed-surface-wrapper-over-raw-storage pattern explored in the 2026-05-22
round (`Ordinal.AtomicPosition<Tag>` and bare-`UInt`/`UInt64` Dictionary
keys with typed surfaces) was reverted on 2026-05-23 on correctness
grounds — the pattern degrades the typed storage discipline. No
landed workaround exists at this time. Resolution: wait for the
Swift 6.5 release.
