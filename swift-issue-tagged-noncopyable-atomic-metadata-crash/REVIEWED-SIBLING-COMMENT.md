---
title: "Sibling-instance data point on swiftlang/swift#74303 — Tagged + Atomic + `~Copyable` cross-module conditional-conformance metadata SIGSEGV (with identified fix)"
target-issue: swiftlang/swift#74303
posture: data-point comment on existing open issue
status: PENDING-ORCHESTRATOR-AUTHORIZATION-TO-POST
date: 2026-05-23
---

> **STATUS** (2026-05-23): pending orchestrator authorization per [`ISSUE-008`].
> Body intended as a comment on [swiftlang/swift#74303](https://github.com/swiftlang/swift/issues/74303),
> NOT a new issue. `89389` is substituted with
> the assigned number after the backport-request issue is filed.

# Sibling-comment body (reviewed)

Sibling instance of the `__swift_instantiateConcreteTypeFromMangledName` null-return family, in a different domain — institute Tagged + Atomic + `~Copyable`.

**Shape.** `Atomic<Tagged<Tag, Ordinal>>.advance(within: Tagged<Tag, Cardinal>)`, where `Tagged<Tag, Underlying>` is a `~Copyable & ~Escapable` phantom-typed wrapper with a conditional `AtomicRepresentable` conformance defined in a sibling SwiftPM module. `__swift_instantiateConcreteTypeFromMangledNameV2` returns null; the call faults dereferencing `[null + 0x10]`. `SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1` prints `failed type lookup for <symbolic-mangled-name>: unknown error` — same early-pipeline `swift_getTypeByMangledName → TypeLookupError("unknown error")` failure mode as the DiscordBM trace.

**Reproducer + CI matrix.** [`swift-institute/Issues/swift-issue-tagged-noncopyable-atomic-metadata-crash/`](https://github.com/swift-institute/Issues/tree/main/swift-issue-tagged-noncopyable-atomic-metadata-crash) — SwiftPM executable, 9 statements in `Sources/Reproducer/main.swift`. CI [run 26326702012](https://github.com/swift-institute/Issues/actions/runs/26326702012):

| Toolchain / platform | Build | Result |
|---|---|---|
| Apple Swift 6.3.2 (Xcode 26.4.1, macOS arm64) | debug | CRASH |
| swift.org `swift-6.3.2-RELEASE` (Ubuntu x86_64) | release | NO CRASH (same source tag as Apple) |
| swift.org main-branch nightly (Ubuntu x86_64) | release | PASS |

**Identified fix.** [`bc44d42f11`](https://github.com/swiftlang/swift/commit/bc44d42f11830ea37a3b882e332ef480c1b4324e) in [PR #87066](https://github.com/swiftlang/swift/pull/87066) (@kavon, merged 2026-02-10) — +14/−0 to `lib/Demangling/Demangler.cpp`, adding cases `'j'` (Inverse + Assoc) and `'J'` (Inverse + CompoundAssoc) to `Demangler::demangleGenericRequirement()`. Present on `release/6.4.x` and `main`; absent from `release/6.3` (verified via `gh api compare`). Separate backport-request issue: swiftlang/swift#`89389`.

Whether `bc44d42f11` also closes this issue (DiscordBM `IntBitField<Flag>?` Codable+Optional) and [#69615](https://github.com/swiftlang/swift/issues/69615) (Kubrick opaque-return-type) depends on whether those failure paths share the inverse-assoc demangler entry — a determination for the runtime maintainers.

---

## Cross-references (for the comment author, not part of the posted comment)

- Local catalog entry: `swift-institute/Research/swift-compiler-bug-catalog.md` §A9 (note: §A9 update labels three snapshots as Swift 6.5-dev; empirically two are 6.4-dev — see AUDIT-REPORT.md C-19).
- Investigation arc: [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md); internal workspace handoffs covering Arcs 1–3 and Arcs 4–5.
- Companion artifact: [`REVIEWED-BACKPORT-REQUEST.md`](REVIEWED-BACKPORT-REQUEST.md).
- Audit: [`AUDIT-REPORT.md`](AUDIT-REPORT.md).

## Posting checklist (for orchestrator review)

- [ ] CI run `26326702012` current — if reproducer drifts before posting, trigger a fresh run.
- [ ] Reproducer link valid (Issues repo `swift-institute/Issues` pushed through `d85cfcc`).
- [ ] `89389` substituted with assigned issue number after backport issue is filed.
- [ ] Post-order: file backport-request issue first; capture its number; substitute placeholder; only then post this comment.
- [ ] No backport-request framing in the comment body — that's the separate issue.
