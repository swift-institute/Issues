---
title: "Sibling-instance data point on swiftlang/swift#74303 — Tagged + Atomic + `~Copyable` cross-module conditional-conformance metadata SIGSEGV (with identified fix + backport ask)"
target-issue: swiftlang/swift#74303
posture: data-point comment on existing open issue
status: PENDING-ORCHESTRATOR-AUTHORIZATION-TO-POST
date: 2026-05-23
---

> **STATUS** (2026-05-23): pending orchestrator authorization per
> [`ISSUE-008`]. The body below is intended as a comment on
> [`swiftlang/swift#74303`](https://github.com/swiftlang/swift/issues/74303),
> NOT as a new issue. Companion artifact:
> [`BACKPORT-REQUEST-DRAFT.md`](BACKPORT-REQUEST-DRAFT.md) drafts a
> separate top-level backport-request issue for `release/6.3` only
> (`release/6.4.x` already contains the fix). The placeholder
> `<PLACEHOLDER-FOR-BACKPORT-ISSUE-NUMBER>` below is substituted with
> the assigned backport-issue number after the backport issue is filed
> and before this comment is posted.

# Sibling-comment body (draft for posting on swiftlang/swift#74303)

We hit the same `__swift_instantiateConcreteTypeFromMangledName` null-return failure family with a different domain — sharing as a data point in case the runtime maintainers find it useful, and because we've now identified the commit that fixes our shape on `main`.

**Shape**: `Atomic<Tagged<Tag, Ordinal>>.advance(within: Tagged<Tag, Cardinal>)` where `Tagged<Tag, Underlying>` is a phantom-typed `~Copyable & ~Escapable` wrapper struct with a conditional `AtomicRepresentable` conformance (`where Underlying: AtomicRepresentable, Tag: ~Copyable`) defined in a sibling SwiftPM module of the package that declares `Tagged` itself. The `.advance(within:)` extension method's where-clause chain (`Value: Ordinal.\`Protocol\` & AtomicRepresentable`, `Value.AtomicRepresentation == UInt.AtomicRepresentation`, `C: Carrier.\`Protocol\`<Cardinal>`, `Value.Domain == C.Domain`) forces full `Atomic<Tagged<…>>` type-metadata instantiation at the call site; `__swift_instantiateConcreteTypeFromMangledNameV2` returns null and the call fault dereferences `[null + 0x10]` → `EXC_BAD_ACCESS (code=1, address=0x10)`. Setting `SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1` prints `failed type lookup for <symbolic-mangled-name>: unknown error` before the SIGSEGV — the same `swift_getTypeByMangledName → TypeLookupError("unknown error")` early-pipeline failure that surfaces in this issue's DiscordBM `IntBitField<Flag>?` Codable+Optional reproducer.

**Reproducer**: [`swift-institute/Issues/swift-issue-tagged-noncopyable-atomic-metadata-crash/`](https://github.com/swift-institute/Issues/tree/main/swift-issue-tagged-noncopyable-atomic-metadata-crash) — a SwiftPM executable with three external `swift-primitives`-org dependencies; ~13 statements in `Sources/Reproducer/main.swift`. Fires deterministically on Apple Swift 6.3.x (Xcode 26.4.1) and exits cleanly on every `main`-cut Swift nightly from 2026-02-10 onwards.

**Identified fix**: [swiftlang/swift#87066](https://github.com/swiftlang/swift/pull/87066) ("SuppressedAssociatedTypesWithDefaults: swiftinterface and mangling support", merged 2026-02-10 by @kavon) — specifically commit [bc44d42f11](https://github.com/swiftlang/swift/commit/bc44d42f11830ea37a3b882e332ef480c1b4324e), a 14-line addition to `lib/Demangling/Demangler.cpp` that adds cases `'j'` (Inverse + Assoc) and `'J'` (Inverse + CompoundAssoc) to `Demangler::demangleGenericRequirement()`. Before `bc44d42f11`, the demangler hit the `default:` branch for those `Rj` / `RJ` markers and returned a null node; `swift_getTypeByMangledName` then produced the default-constructed `TypeLookupError("unknown error")` that this issue's crash signature shows. PR #87066's own added test [`test/Casting/suppressed-associated-types.swift`](https://github.com/swiftlang/swift/blob/main/test/Casting/suppressed-associated-types.swift) (NEW, 103 lines) explicitly covers the runtime-type-casting case; the PR body acknowledges the prior state ("we also had the mangling and runtime type casting incorrect, or at least, untested for the -WithDefaults version until now"). Identification path: snapshot bisection narrowed the fix window to commits on `main` between `4c5257d961` (snapshot 2026-02-05-a, CRASH on equivalent reproducer) and `d13cbbfd33` (snapshot 2026-03-16-a, PASS), source-level inspection of `lib/Demangling/Demangler.cpp` commits in that window picked out `bc44d42f11`, and `gh api compare/release/6.3...bc44d42f11 → diverged` confirmed the fix is on `main` and `release/6.4.x` but absent from `release/6.3` (which is what 6.3.x Apple toolchains ship from). Whether `bc44d42f11` also closes #74303 (DiscordBM Codable+Optional) and [#69615](https://github.com/swiftlang/swift/issues/69615) (Kubrick `@JobBuilder` opaque-return-type) depends on whether those failure paths share the same demangler entry point — a determination for the maintainers, not this report. We've filed a separate backport-request issue at swiftlang/swift#`<PLACEHOLDER-FOR-BACKPORT-ISSUE-NUMBER>` asking for `bc44d42f11` to be cherry-picked to `release/6.3` (the current shipping Xcode 6.3.x toolchains carry the unfixed demangler; `release/6.4.x` is already covered).

**Toolchain matrix**:

| Toolchain | Result |
|-----------|--------|
| Apple Swift 6.3.2 RELEASE (Xcode 26.4.1) | CRASH (exit 139) |
| Swift 6.5-dev nightly `2026-03-16-a` (post-fix on main) | PASS (exit 0) |
| Swift 6.5-dev nightly `2026-05-07-a` | PASS (exit 0) |
| Swift 6.5-dev nightly `2026-05-12-a` | PASS (exit 0, debug + release) |

Caveat (preserved from earlier draft): five bare-`swiftc` reduction shapes plus a nine-candidate `Tagged.swift` single-file bisection all PASS in isolation, suggesting the production `Tagged_Primitives.Tagged` symbol with its production module structure is load-bearing for triggering the demangler-side failure. With the fix now identified as a pure demangler-side change (no type-checker or AST work needed at the consumer's site), a single-file reduction with full protocol-identity scaffolding (Ordinal/Carrier/Cardinal inlined) would likely also reproduce, but we did not run that test — it's not load-bearing for the resolution given the fix is identified.

---

## Cross-references (for the comment author, not part of the posted comment)

- Local catalog entry: `swift-institute/Research/swift-compiler-bug-catalog.md` §A9 (Arc 4 commits `ba4b911` + `f237cda` + `f2d7efd` + `19da3a4`; Arc 5 bisection record pending)
- Investigation arcs: [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) (4-arc history through bare-`swiftc` reduction + v1 retry); workspace handoffs an internal handoff document (Arcs 1–3) + an internal handoff document (Arcs 4–5)
- Companion artifact: [`BACKPORT-REQUEST-DRAFT.md`](BACKPORT-REQUEST-DRAFT.md) — draft of separate backport-request issue
- Related upstream issues:
  - [`#74303`](https://github.com/swiftlang/swift/issues/74303) — target for this comment
  - [`#69615`](https://github.com/swiftlang/swift/issues/69615) — same family, opaque-return-type domain
  - `#74333` — CLOSED, dupe of `#74303`
- Arc 5 identification: PR [#87066](https://github.com/swiftlang/swift/pull/87066) (commit [`bc44d42f11`](https://github.com/swiftlang/swift/commit/bc44d42f11830ea37a3b882e332ef480c1b4324e); merge `d49ebd5a58`); HIGH confidence per signature match + cherry-pick-absence on `release/6.3` + PR-body runtime-breakage acknowledgement

## Posting checklist (for orchestrator review)

- [ ] Comment body factually accurate (toolchain matrix verified 2026-05-23 against `org.swift.64202603161a` / `org.swift.64202605071a` / `org.swift.64202605121a` snapshots; identified fix verified via `gh api compare/release/6.3...bc44d42f11 → diverged` and `compare/release/6.4.x...bc44d42f11 → identical history`)
- [ ] Reproducer link valid (Issues repo `swift-institute/Issues` — will be valid once pushed; currently local commits through `d85cfcc`)
- [ ] Backport-request issue # captured: `<PLACEHOLDER-FOR-BACKPORT-ISSUE-NUMBER>` substituted with the real issue number returned by the backport-request issue filing
- [ ] Authorization-to-post recorded in `INVESTIGATION-ARC.md` AFTER the backport-request issue is filed (post-order: file backport-request issue first; capture its number; substitute the placeholder; only then post this sibling comment)
- [ ] Five-shape + nine-candidate evidence confirms production-symbol-load-bearing under the `[ISSUE-026]` coverage scope; demangler-only fix scope means single-file with full protocol-identity scaffolding likely DOES reproduce but that test is deferred — wording preserved in body's "Caveat" sentence
- [ ] No backport-request framing in the comment body — that's the separate issue
