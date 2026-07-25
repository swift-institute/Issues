---
title: "[release/6.3] Backport request: PR #87066 (Demangler: inverse assoc type demangling) — fix for `Atomic<Tagged<…>>` runtime metadata SIGSEGV in Apple Swift 6.3.x"
target-issue: NEW (filed-as: TBD)
posture: backport request
target-branches: release/6.3 only — release/6.4.x already contains bc44d42f11 (verified)
status: PENDING-ORCHESTRATOR-AUTHORIZATION-TO-POST
date: 2026-05-23
venue-precedent: swiftlang/swift#88239 ("Serialized explicit module paths … on release/6.3" — same shape: bug report titled with affected branch, body notes "fixed on main", asks for handling on release branch). swiftlang/swift uses no dedicated backport-request issue type; cherry-picks are maintainer-filed PRs (label `🍒 release cherry pick`); external reporters file regular bug-tracker issues that flag affected branches in the title.
---

> **WITHDRAWN (2026-05-28).** This backport request was filed as
> [swiftlang/swift#89389](https://github.com/swiftlang/swift/issues/89389) and
> then **withdrawn**. Its central premise — that the crash is a demangler gap
> fixable by cherry-picking `bc44d42f11` to `release/6.3` — is **wrong**. A
> compiler/runtime swap shows the fault is compiler **emission (codegen)**, not
> the demangler: `bc44d42f11` (demangler-only) would not fix 6.3-compiled code.
> This is the incomplete-on-6.3 `SuppressedAssociatedTypes` feature. See
> INVESTIGATION-ARC.md Arc 7, catalog §A9 Correction (2026-05-28), and the
> withdrawal reply at #89389 comment 4563419364. The draft below is retained as
> historical record only — do not act on it.
>
> ---
>
> **STATUS** (2026-05-23, superseded): pending orchestrator authorization per
> [`ISSUE-008`]. The body below is intended as a NEW top-level issue
> on swiftlang/swift, following the standard Swift bug-template shape
> with affected-branch tag in the title (precedent:
> [swiftlang/swift#88239](https://github.com/swiftlang/swift/issues/88239)).
> Posting requires explicit YES from the orchestrator.

# Backport-request issue body (draft)

### Description

[swiftlang/swift#87066](https://github.com/swiftlang/swift/pull/87066) ("SuppressedAssociatedTypesWithDefaults: swiftinterface and mangling support", merged 2026-02-10 by @kavon, merge commit `d49ebd5a58e72067535b50f502b99947ba2a903a`) added support for demangling `Rj` / `RJ` inverse-associated-type generic-requirement markers. Without this support, the runtime's `swift_getTypeByMangledName` returns a default-constructed `TypeLookupError("unknown error")` for any cross-module conditional conformance whose mangled name contains those markers (notably any conformance constraint of the form `where Tag: ~Copyable` on a generic type), and the caller's metadata-lookup stub `__swift_instantiateConcreteTypeFromMangledNameV2` then stores the null result and faults on the first dereference.

The fix has landed on `main` and is reachable from `release/6.4.x` (`bc44d42f11` is present in that branch — verified via `gh api compare/release/6.4.x...bc44d42f11`). However, the fix is **not** on `release/6.3` (verified via `gh api compare/release/6.3...bc44d42f11` → `diverged`; no commit on `release/6.3` or `release/6.3.1` matches `bc44d42f11` / PR #87066 / "inverse assoc"). All currently shipping Apple Swift 6.3.x toolchains (most recently Swift 6.3.2 RELEASE in Xcode 26.4.1, tag `swift-6.3.2-RELEASE` at `cd8d8ad001`) carry the unfixed demangler.

This is a runtime regression in Apple Swift 6.3.x relative to Apple Swift 6.4 and later: code that compiles cleanly on 6.3.x with an unflagged warning-free build can still SIGSEGV at runtime the first time a cross-module conditional conformance with a `~Copyable` constraint is materialized inside a generic stdlib container (we observe this for `Atomic<Tagged<…>>` and for `Dictionary<TaggedKey, ~CopyableValue>` shapes).

We would appreciate, if the release-management team can consider it, a cherry-pick of #87066 (or at least the runtime-relevant subset — see "Scope" below) to `release/6.3`.

### Reproduction

Full reproducer is staged publicly at [swift-institute/Issues/swift-issue-tagged-noncopyable-atomic-metadata-crash/](https://github.com/swift-institute/Issues/tree/main/swift-issue-tagged-noncopyable-atomic-metadata-crash) — SwiftPM executable with three external `swift-primitives`-org dependencies, ~13 statements in `Sources/Reproducer/main.swift`:

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

```bash
$ swift run swift-issue-tagged-noncopyable-atomic-metadata-crash-Repro
# Apple Swift 6.3.2 (Xcode 26.4.1): killed by SIGSEGV; exit 139
# Swift 6.5-dev nightly 2026-03-16-a / 2026-05-07-a / 2026-05-12-a:  prints "result = 0"; exit 0
```

`lldb` confirms the fault is on the first instruction of `Atomic<Tagged<Tag, Ordinal>>.advance(within:)` dereferencing the null metadata pointer returned by `__swift_instantiateConcreteTypeFromMangledNameV2`:

```
EXC_BAD_ACCESS (code=1, address=0x10)
Frame: Atomic<Tagged_Primitives.Tagged<Tag, Ordinal_Primitive.Ordinal>>.advance(within:) + 92
  → __swift_instantiateConcreteTypeFromMangledNameV2  (returns null)
  → libswiftCore.dylib`swift_getTypeByMangledNameInContext2
  → libswiftCore.dylib`swift_getTypeByMangledNameInContextImpl
  → libswiftCore.dylib`swift_getTypeByMangledName
       ↳ returns TypeLookupErrorOr{ tag = 1, message = "unknown error" }
```

`SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1` prints `failed type lookup for <symbolic-mangled-name>: unknown error` before the SIGSEGV.

A bare-`swiftc` single-file reduction is not achievable: the bug requires the production `Tagged_Primitives.Tagged` symbol with its production module structure (five reduction shapes attempted in single-file and multi-module variants, all PASS in isolation; the production module structure is empirically load-bearing for triggering the demangler-side failure).

### Expected behavior

Same as on `release/6.4.x` (and on every `main`-cut nightly from 2026-02-10 onwards): the demangler resolves the `Rj` / `RJ` markers, the runtime materializes the metadata for `Atomic<Tagged_Primitives.Tagged<…>>` correctly, and the program runs without faulting.

### Environment

| Component | Value |
|-----------|-------|
| Apple toolchain (broken) | Swift 6.3.2 RELEASE (`swiftlang-6.3.2.1.108`), Xcode 26.4.1 |
| Branch of broken toolchain | `release/6.3` (Apple swift-6.3.2-RELEASE tag at `cd8d8ad001`); `release/6.3.1` shares the lineage |
| Earlier broken Apple toolchain | Swift 6.3.1 RELEASE (`swiftlang-6.3.1.1.2`), Xcode 26.4 |
| Branch of fixed toolchain | `main` (since `d49ebd5a58`, 2026-02-10); `release/6.4.x` (already contains `bc44d42f11`) |
| Verified fixed nightlies (main) | Swift 6.5-dev `2026-03-16-a` (`org.swift.64202603161a`), `2026-05-07-a` (`org.swift.64202605071a`), `2026-05-12-a` (`org.swift.64202605121a`) |
| Platform | macOS 26.2 (build 25C56), arm64. Linux/Windows not yet verified empirically; the failure mode (runtime metadata demangler) is platform-independent so the same bug likely affects every host. |
| Build configurations affected | both `-Onone` and `-O` reproduce on 6.3.x; both PASS on `main` / `release/6.4.x` |

### Scope of cherry-pick

[PR #87066](https://github.com/swiftlang/swift/pull/87066) is a multi-file change (totaling ~250 lines across 10 files):

| File | Change |
|------|--------|
| `lib/Demangling/Demangler.cpp` | **+14 / −0** — the runtime-side demangler fix in commit `bc44d42f11`. Adds cases `'j'` (Inverse + Assoc) and `'J'` (Inverse + CompoundAssoc) to `Demangler::demangleGenericRequirement()`, replacing the prior `default:` fall-through. |
| `lib/AST/GenericSignature.cpp` | +99 / −10 — `getRequirementsWithInverses` update (commit `b2e698ec41`); affects mangled-name *emission* on the producer side. |
| `lib/AST/ASTMangler.cpp`, `lib/AST/ASTPrinter.cpp`, `include/swift/AST/Requirement.h`, `lib/AST/Requirement.cpp`, `lib/IRGen/GenProto.cpp` | minor (-1 to +9 per file) |
| `test/Casting/suppressed-associated-types.swift` (NEW, 103 lines) | Explicit test for the runtime-type-casting case the PR body acknowledged was previously "incorrect, or at least, untested". |
| `test/Demangle/Inputs/manglings.txt`, `test/ModuleInterface/associated_type_suppressed.swift` (NEW, 97 lines) | Mangling and module-interface coverage. |

The minimal runtime-impact subset for the SIGSEGV we observe is `bc44d42f11` alone (the demangler-side fix). The Apple Swift 6.3.x compiler already *emits* `Rj` / `RJ` markers in its mangled names — we see them in our crash signature; what's missing is the demangler's ability to *read* them. Cherry-picking only `bc44d42f11` plus its added test (`test/Casting/suppressed-associated-types.swift`) should be sufficient to close the runtime regression. The maintainers' judgement on what to take from PR #87066 supersedes any external preference — we mention this only to flag that the full PR's mangler / AST changes affect emitted mangled names and may have wider compatibility implications, while the demangler-side change does not.

### Additional information

- Production impact: four call sites across three Swift-Institute packages currently SIGSEGV at test time on Apple Swift 6.3.2:
  - `swift-foundations/swift-executors/Sources/Executors/Kernel.Thread.Executor.Sharded.swift:46,57` — `Atomic<Index<Kernel.Thread>>`
  - `swift-foundations/swift-executors/Sources/Executors/Kernel.Thread.Executor.Stealing.swift:57` — `Atomic<Index<Kernel.Thread>>`
  - `swift-foundations/swift-kernel/Sources/Kernel Event/Kernel.Event.Driver.swift:103` — `Dictionary_Primitives.Dictionary<Kernel.Event.ID, Registration>`
  - `swift-foundations/swift-io/Sources/IO Completions/Completion.Actor.swift:86` — `Dictionary<Kernel.Completion.Token, Completion.Entry>` (stdlib `Dictionary`, `~Copyable` `Value`)

- An Institute-side typed-surface-wrapper-over-raw-storage workaround was attempted (raw `UInt`/`UInt64` internal storage with `Tagged` surface API), but rejected on correctness grounds (degrades the typed phantom-Tag discipline at the storage layer rather than fixing the cause). No landed workaround exists.

- Internal Apple radar referenced by PR #87066: rdar://169536826.

- Related sibling instances of the same `__swift_instantiateConcreteTypeFromMangledName`-null-return failure family (different domains, both currently OPEN on swiftlang/swift):
  - [#74303](https://github.com/swiftlang/swift/issues/74303) — DiscordBM `IntBitField<Flag>?` Codable+Optional (closed dupe: #74333).
  - [#69615](https://github.com/swiftlang/swift/issues/69615) — Kubrick `@JobBuilder buildBlock` opaque-return-type.
  - The mechanism `bc44d42f11` addresses (missing demangler cases for inverse-conformance markers) is specifically the `~Copyable`-Tag-suppression sub-family. Whether the fix also closes #74303 / #69615 depends on whether those failure paths share the same demangler entry point; that determination is for the runtime maintainers, not this report.

- Workspace investigation arc (4 investigation rounds + this Arc 5 bisection): [`INVESTIGATION-ARC.md`](https://github.com/swift-institute/Issues/blob/main/swift-issue-tagged-noncopyable-atomic-metadata-crash/INVESTIGATION-ARC.md).

### Ask

Would the release-management team consider cherry-picking #87066 (or at minimum the demangler subset `bc44d42f11`) to `release/6.3`? This would close the runtime regression for the next Apple Swift 6.3.x point release that ships with Xcode. We're flexible on the cherry-pick scope and happy to defer to maintainer judgement on what's safe to backport.

`release/6.4.x` is already covered (verified to contain `bc44d42f11`); no action needed there.

Thank you for your time.

---

## Cross-references (for the author, not part of the posted issue)

- Local catalog entry: `swift-institute/Research/swift-compiler-bug-catalog.md` §A9 (commits `ba4b911` + Arc 4 corrections `f237cda` + `f2d7efd` + `19da3a4`)
- Investigation arcs: [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md), internal workspace records covering Arcs 1–3 and Arcs 4–5
- Arc 5 bisection record (commit identification): pending append after orchestrator authorization

## Posting checklist (for orchestrator review)

- [ ] Title shape `[release/6.3] Backport request: …` matches the closest convention precedent (#88239 uses the same "title flags affected branch" style). swiftlang/swift has no dedicated backport-request issue type; cherry-picks themselves are maintainer-filed PRs.
- [ ] Cherry-pick state verified: `bc44d42f11` absent from `release/6.3` and `release/6.3.1`, present on `release/6.4.x` and `main` (verified via `gh api compare/…`).
- [ ] Body uses the Swift bug template (Description / Reproduction / Expected behavior / Environment / Additional information) plus a "Scope of cherry-pick" section between Environment and Additional information.
- [ ] Ask phrased deferentially (no demand framing).
- [ ] Reproducer link valid (Issues repo `swift-institute/Issues`; commits local — push happens before posting).
- [ ] No `<PLACEHOLDER>` strings left in the body.
- [ ] Orchestrator-authorization recorded in `INVESTIGATION-ARC.md` before posting.
- [ ] After posting, the assigned issue number is substituted into `SIBLING-COMMENT-DRAFT.md`'s `<PLACEHOLDER-FOR-BACKPORT-ISSUE-NUMBER>` placeholder.
