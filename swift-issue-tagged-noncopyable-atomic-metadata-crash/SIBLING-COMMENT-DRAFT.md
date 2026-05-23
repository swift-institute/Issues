---
title: "Sibling-instance data point on swiftlang/swift#74303 — Tagged + Atomic + `~Copyable` cross-module conditional-conformance metadata SIGSEGV"
target-issue: swiftlang/swift#74303
posture: data-point comment on existing open issue
status: PENDING-ORCHESTRATOR-AUTHORIZATION-TO-POST
date: 2026-05-23
---

> **STATUS** (2026-05-23): pending orchestrator authorization per
> [`ISSUE-008`]. The body below is intended as a comment on
> [`swiftlang/swift#74303`](https://github.com/swiftlang/swift/issues/74303),
> NOT as a new issue and NOT as a 6.3.x-backport request. Posting
> requires explicit YES from the orchestrator.

# Sibling-comment body (draft for posting on swiftlang/swift#74303)

We hit the same `__swift_instantiateConcreteTypeFromMangledName` null-return failure family with a different domain — sharing as a data point in case the fix scope here also covers our shape.

**Shape**: `Atomic<Tagged<Tag, Ordinal>>.advance(within: Tagged<Tag, Cardinal>)` where `Tagged<Tag, Underlying>` is a phantom-typed `~Copyable & ~Escapable` wrapper struct with a conditional `AtomicRepresentable` conformance (`where Underlying: AtomicRepresentable, Tag: ~Copyable`) defined in a sibling SwiftPM module of the package that declares `Tagged` itself. The `.advance(within:)` extension method's where-clause chain (`Value: Ordinal.\`Protocol\` & AtomicRepresentable`, `Value.AtomicRepresentation == UInt.AtomicRepresentation`, `C: Carrier.\`Protocol\`<Cardinal>`, `Value.Domain == C.Domain`) forces full `Atomic<Tagged<…>>` type-metadata instantiation at the call site; `__swift_instantiateConcreteTypeFromMangledNameV2` returns null and the call fault dereferences `[null + 0x10]` → `EXC_BAD_ACCESS (code=1, address=0x10)`. Setting `SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1` prints `failed type lookup for <symbolic-mangled-name>: unknown error` before the SIGSEGV — the same `swift_getTypeByMangledName → TypeLookupError("unknown error")` early-pipeline failure that surfaces in this issue's DiscordBM `IntBitField<Flag>?` Codable+Optional reproducer.

**Reproducer**: [`swift-institute/Issues/swift-issue-tagged-noncopyable-atomic-metadata-crash/`](https://github.com/swift-institute/Issues/tree/main/swift-issue-tagged-noncopyable-atomic-metadata-crash) — a SwiftPM executable with three external `swift-primitives`-org dependencies (`swift-tagged-primitives` + `swift-ordinal-primitives` + `swift-cardinal-primitives`); 13 statements in `Sources/Reproducer/main.swift`. The reproducer fires deterministically on the buggy toolchain and exits cleanly on the fixed one. A bare-`swiftc` single-file reduction was attempted across four simplified-Tagged shapes and none reproduced; the v1 full-attribute-single-file variant with the required flag scaffolding (`-package-name` + `-enable-experimental-feature Lifetimes`) was not retried — that hypothesis is still open. The four simplified shapes plus a nine-candidate `Tagged.swift` single-file bisection suggest (but do not prove) that the production `Tagged_Primitives.Tagged` symbol with its production module structure is load-bearing.

**Toolchain matrix**:

| Toolchain | Result |
|-----------|--------|
| Apple Swift 6.3.2 RELEASE (Xcode 26.4.1) | CRASH (exit 139) |
| Swift 6.5-dev nightly `2026-03-16-a` | PASS (exit 0) |
| Swift 6.5-dev nightly `2026-05-07-a` | PASS (exit 0) |
| Swift 6.5-dev nightly `2026-05-12-a` | PASS (exit 0, debug + release) |

The fix landed somewhere in the 6.4-dev nightly stream between 6.3.2's release and `2026-03-16-a`.

**Ask**: which commit landed the fix? Knowing the commit helps confirm whether the fix scope here covers the sibling instances at #74303 (DiscordBM Codable+Optional) and [#69615](https://github.com/swiftlang/swift/issues/69615) (Kubrick `@JobBuilder` opaque-return-type) — both of which are still open and may or may not be resolved by the same change. If the fix is generally in the demangler's early-pipeline `swift_getTypeByMangledName` path, all three sibling instances likely share resolution.

---

## Cross-references (for the comment author, not part of the posted comment)

- Local catalog entry: `swift-institute/Research/swift-compiler-bug-catalog.md` §A9 (commit `ba4b911`, updated `f237cda`)
- Investigation arc: [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) — full 4-arc history
- Workspace handoffs: `HANDOFF-test-sigsegv-post-cycle-break.md`, `HANDOFF-tagged-noncopyable-atomic-metadata-crash.md`
- Related upstream issues:
  - [`#74303`](https://github.com/swiftlang/swift/issues/74303) — target for this comment
  - [`#69615`](https://github.com/swiftlang/swift/issues/69615) — same family, opaque-return-type domain
  - `#74333` — CLOSED, dupe of `#74303`

## Posting checklist (for orchestrator review)

- [ ] Comment body factually accurate (toolchain matrix verified 2026-05-23 against `org.swift.64202603161a` / `org.swift.64202605071a` / `org.swift.64202605121a` snapshots)
- [ ] Reproducer link valid (Issues repo `swift-institute/Issues` — will be valid once pushed; currently local commits `336cbe8` + corrections commit pending)
- [ ] Implicit ask phrased neutrally (no demand; just "which commit?" as a data-point follow-up)
- [ ] No backport-request framing (per orchestrator filing-posture decision 2026-05-23)
- [ ] No claim that v1 bare-`swiftc` is "fundamentally" unreducible (per [`ISSUE-026`] coverage-scope discipline; v1 was not tested)
- [ ] Orchestrator authorization to post recorded in `INVESTIGATION-ARC.md` before posting
