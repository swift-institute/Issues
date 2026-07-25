---
title: "[release/6.3] Backport request: PR #87066 (Demangler inverse-assoc cases) — fix for `Atomic<Tagged<…>>` runtime metadata SIGSEGV in Apple Swift 6.3.x"
target-issue: NEW (filed-as: TBD)
posture: backport request
target-branches: release/6.3 only — release/6.4.x already contains bc44d42f11 (verified)
status: PENDING-ORCHESTRATOR-AUTHORIZATION-TO-POST
date: 2026-05-23
venue-precedent: swiftlang/swift#88239 (title flags affected branch; external reporters file regular bug-tracker issues — swiftlang/swift has no dedicated backport-request type)
---

> **STATUS** (2026-05-23): pending orchestrator authorization per
> [`ISSUE-008`]. Body intended as a NEW top-level issue on swiftlang/swift.

# Backport-request issue body (reviewed)

### Description

Commit [`bc44d42f11`](https://github.com/swiftlang/swift/commit/bc44d42f11830ea37a3b882e332ef480c1b4324e) in [PR #87066](https://github.com/swiftlang/swift/pull/87066) ("SuppressedAssociatedTypesWithDefaults: swiftinterface and mangling support", merged 2026-02-10 by @kavon) adds cases `'j'` (Inverse + Assoc) and `'J'` (Inverse + CompoundAssoc) to `Demangler::demangleGenericRequirement()` in `lib/Demangling/Demangler.cpp` (+14/−0). Without these cases the demangler falls through `default:` for `Rj` / `RJ` inverse-associated-type markers; `swift_getTypeByMangledName` returns `TypeLookupError("unknown error")` and the caller's `__swift_instantiateConcreteTypeFromMangledNameV2` stub stores null metadata that subsequently faults on dereference.

Cherry-pick state (verified via `gh api compare/<branch>...bc44d42f11`):

| Branch | Contains `bc44d42f11`? |
|--------|------------------------|
| `release/6.3`, `release/6.3.1` | No (diverged) |
| `release/6.4.x` | Yes (branch is `behind`; `bc44d42f11` is merge-base) |
| `main` | Yes |

### Cross-platform CI matrix

CI [run 26326702012](https://github.com/swift-institute/Issues/actions/runs/26326702012) on commit `d85cfcc` of the reproducer:

| Toolchain | Platform / arch | Build | Result |
|-----------|-----------------|-------|--------|
| Apple Swift 6.3.2 RELEASE (Xcode 26.4.1) | macOS 26.4 arm64 | debug | CRASH (`exited with unexpected signal code 11`) |
| swift.org `swift-6.3.2-RELEASE` | Ubuntu 24.04 x86_64 | release | NO CRASH (`withKnownIssue` body ran cleanly; `Known issue was not recorded`) |
| swift.org `swift-6.3.2-RELEASE` | Windows Server 2025 x86_64 | debug | exit code 1, no SwiftTesting summary (inconclusive) |
| swift.org main-branch nightly (Swift commit `cf0aed5b19d`) | Ubuntu 24.04 x86_64 | release | PASS |

The macOS-vs-Linux comparison varies on two axes (platform and build configuration). Local testing on the same Apple Xcode 6.3.2 reports CRASH under both `-Onone` and `-O`, which is consistent with — though not equivalent to — a platform-driven discriminator. CI-only confidence is: "Apple Xcode 6.3.2 macOS arm64 debug crashes; swift.org Linux 6.3.2 x86_64 release does not, on the same `swift-6.3.2-RELEASE` source tag (`cd8d8ad001`)."

### Reproducer

[`swift-institute/Issues/swift-issue-tagged-noncopyable-atomic-metadata-crash/`](https://github.com/swift-institute/Issues/tree/main/swift-issue-tagged-noncopyable-atomic-metadata-crash) — SwiftPM executable, three `swift-primitives`-org dependencies, 9 statements in `Sources/Reproducer/main.swift`:

```swift
import Synchronization
import Tagged_Primitives
import Ordinal_Primitives
import Cardinal_Primitives

enum SimpleTag: Sendable {}
let cursor = Atomic<Tagged<SimpleTag, Ordinal>>(.zero)
let count: Tagged<SimpleTag, Cardinal> = try! .init(2)
let result = cursor.advance(within: count)
print("result = \(result.underlying.rawValue)")
```

`lldb` pins the fault on the first instruction of `Atomic<Tagged<…>>.advance(within:)` dereferencing null metadata returned by `__swift_instantiateConcreteTypeFromMangledNameV2`. `SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1` prints `failed type lookup for <symbolic-mangled-name>: unknown error` before the SIGSEGV. Bare-`swiftc` reduction across five shapes did not reproduce — the production `Tagged_Primitives.Tagged` symbol with its production module structure is load-bearing for triggering the demangler path.

Internal Apple radar referenced by PR #87066: rdar://169536826. Related open issues in the same `__swift_instantiateConcreteTypeFromMangledName` null-return family (different domains): [#74303](https://github.com/swiftlang/swift/issues/74303), [#69615](https://github.com/swiftlang/swift/issues/69615) — whether `bc44d42f11` closes them is for the runtime maintainers.

### Ask

If `bc44d42f11` is appropriate for `release/6.3`, we would appreciate a cherry-pick. Given the empirical macOS-only pattern under the same `swift-6.3.2-RELEASE` tag, the defect's locus may be in Apple-downstream toolchain artifacts rather than `release/6.3` itself — release management is better placed than us to judge whether an upstream cherry-pick or Apple Feedback Assistant (rdar://169536826) is the right channel. We're flexible on scope and defer to maintainer judgement on what is safe to backport. `release/6.4.x` is already covered. Thank you.

---

## Cross-references (for the author, not part of the posted issue)

- Local catalog entry: `swift-institute/Research/swift-compiler-bug-catalog.md` §A9 (note: §A9 update table labels three snapshots as "Swift 6.5-dev"; empirically two of those snapshots are 6.4-dev — see AUDIT-REPORT.md C-19).
- Investigation arc: [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md); internal workspace handoffs covering Arcs 1–3 and Arcs 4–5.
- Audit: [`AUDIT-REPORT.md`](AUDIT-REPORT.md) — pre-post claim audit; this file is the substantiated version.

## Posting checklist (for orchestrator review)

- [ ] Every claim cited to verifiable source (PR #, commit SHA, file:line, CI run/job ID).
- [ ] CI run `26326702012` is current — if the reproducer drifts before posting, trigger a fresh run and update the table.
- [ ] Title format `[release/6.3] Backport request: …` aligned with #88239 precedent.
- [ ] No `<PLACEHOLDER>` strings left.
- [ ] Orchestrator-authorization recorded in `INVESTIGATION-ARC.md` before posting.
- [ ] Backport issue number captured after posting and substituted into `REVIEWED-SIBLING-COMMENT.md`.
