---
title: "Pre-post audit — BACKPORT-REQUEST-DRAFT.md + SIBLING-COMMENT-DRAFT.md (Arc 6)"
date: 2026-05-23
auditor: pre-post audit subordinate (per HANDOFF-arc-6-pre-post-audit.md)
auditee: Arc 6 staged drafts (BACKPORT-REQUEST-DRAFT.md, SIBLING-COMMENT-DRAFT.md)
status: COMPLETE — no structural failure; nine non-structural corrections applied to REVIEWED-* outputs
companion-outputs:
  - REVIEWED-BACKPORT-REQUEST.md
  - REVIEWED-SIBLING-COMMENT.md
---

# Audit summary

**Verdict**: no structural failure. The central fix-identification holds (PR #87066 / `bc44d42f11` / +14/−0 in `Demangler.cpp` / absent from `release/6.3` and `release/6.3.1` / present on `release/6.4.x` and `main`). Nine non-structural claims required correction or refinement; one new empirical confound was surfaced (macOS CI runs `-c debug`, Linux 6.3 CI runs `-c release`, so the platform-vs-build-mode discriminator is not isolated by CI alone). Reviewed drafts incorporate all corrections; original drafts preserved unchanged as historical artifacts per the brief's "Do Not Touch" boundary.

**Length budgets met**:

- `REVIEWED-BACKPORT-REQUEST.md` body: **297 words** (budget ≤ 350) — excluding code blocks, tables, headings.
- `REVIEWED-SIBLING-COMMENT.md` body: **168 words** (budget ≤ 200) — same exclusion.

**Verification trail**: 27 claims inventoried; every claim that survives in the REVIEWED-* outputs is cited to a verifiable source (gh API call, file:line, commit SHA, CI run/job ID, local `swift --version`).

---

## Claim inventory + verification result

### Section A — External GitHub facts (PR / commit / branch / issue)

| ID | Claim | Verification method | Verified result | Action |
|----|-------|---------------------|-----------------|--------|
| C-01 | PR #87066 exists | `gh pr view 87066 --repo swiftlang/swift` | EXISTS, state=MERGED | KEEP |
| C-02 | PR #87066 title: "SuppressedAssociatedTypesWithDefaults: swiftinterface and mangling support" | same | EXACT MATCH | KEEP |
| C-03 | PR #87066 merged 2026-02-10 by @kavon | same | `mergedAt:"2026-02-10T11:04:16Z"`, author `kavon` | KEEP |
| C-04 | PR #87066 merge commit `d49ebd5a58e72067535b50f502b99947ba2a903a` | same | EXACT MATCH | KEEP |
| C-05 | Commit `bc44d42f11` adds +14/−0 to `lib/Demangling/Demangler.cpp` | `gh api repos/swiftlang/swift/commits/bc44d42f11830ea37a3b882e332ef480c1b4324e` | EXACT MATCH; the commit modifies *only* this one file | KEEP |
| C-06 | `bc44d42f11` adds cases `'j'` (Inverse + Assoc) and `'J'` (Inverse + CompoundAssoc) to `Demangler::demangleGenericRequirement()` ahead of the prior `default:` line | inspected `.files[0].patch` from same API call | EXACT MATCH; patch shows `case 'j': ConstraintKind = Inverse; TypeKind = Assoc;` and `case 'J': ConstraintKind = Inverse; TypeKind = CompoundAssoc;` immediately before the unchanged `default:` row | KEEP |
| C-07 | Commit author of `bc44d42f11` is Kavon Farvardin; commit date 2026-02-08 | same | MATCH (commit 2026-02-08; PR merged 2026-02-10) | KEEP |
| C-08 | PR #87066 contains a separate commit `b2e698ec4105c37ed69d7e96e63ad7965ab0d8d4` updating `getRequirementsWithInverses` | `gh api repos/swiftlang/swift/pulls/87066/commits` | MATCH (3 commits in PR: `e15d8ec7…` reparenting/test-only, `bc44d42f11…` demangler, `b2e698ec41…` AST + IRGen + tests) | KEEP |
| C-09 | `lib/AST/GenericSignature.cpp` change is +99/−10 inside PR #87066 | `gh pr view 87066 --json files` | EXACT MATCH (path attributed to commit `b2e698ec41` per draft) | KEEP |
| C-10 | PR #87066 totals "~250 lines across 10 files" | `gh pr view 87066 --json files` aggregate | 10 files MATCH; line count is **+327 / −28** (355 changed lines total) — "~250" is a noticeable underestimate | **CORRECTED** — REVIEWED-* outputs drop the misleading total-line claim |
| C-11 | `test/Casting/suppressed-associated-types.swift` added with 103 lines | `gh pr view 87066 --json files` (additions:103) | EXACT MATCH for ADDED line count; current file on `main` is 171 lines (subsequent commits extended it) — keep the "+103 lines as ADDED in PR" framing | KEEP (qualifier "added 103 lines" is unambiguous) |
| C-12 | `test/ModuleInterface/associated_type_suppressed.swift` added with 97 lines | same | EXACT MATCH | KEEP |
| C-13 | `release/6.3` does not contain `bc44d42f11` | `gh api compare/release/6.3...bc44d42f11` | `status: diverged`, `ahead_by: 2251`, `behind_by: 597`, `merge_base: 2db0e8aea80c9d2077eb920be3a0a4cc01385078` | KEEP |
| C-14 | `release/6.3.1` does not contain `bc44d42f11` | `gh api compare/release/6.3.1...bc44d42f11` | `status: diverged`, `ahead_by: 2251`, `behind_by: 544` | KEEP |
| C-15 | `release/6.4.x` contains `bc44d42f11` (it is on the branch's history) | `gh api compare/release/6.4.x...bc44d42f11` | `status: behind`, `ahead_by: 0`, `behind_by: 3101`, `merge_base: bc44d42f11…` — `bc44d42f11` is an ancestor of `release/6.4.x` | KEEP |
| C-16 | Tag `swift-6.3.2-RELEASE` resolves to commit `cd8d8ad001…` | `gh api repos/swiftlang/swift/git/refs/tags/swift-6.3.2-RELEASE` | EXACT MATCH (full sha `cd8d8ad0019e4e291906b311e0d25d7039cddc9c`) | KEEP |
| C-17 | Snapshot SHA `4c5257d961` corresponds to 2026-02-05 | `gh api repos/swiftlang/swift/commits/4c5257d961` | MATCH (full sha `4c5257d961b9eb548915b0c0418e0010be4a984e`, date `2026-02-05T17:27:07Z`) | KEEP |
| C-18 | Snapshot SHA `d13cbbfd33` corresponds to 2026-03-16 | `gh api repos/swiftlang/swift/commits/d13cbbfd33` | MATCH (full sha `d13cbbfd336f246d29e6bfdfe74568fab93ac8af`, date `2026-03-16T08:16:56Z`) | KEEP |
| C-19 | "Swift 6.5-dev nightly `2026-03-16-a` / `2026-05-07-a` / `2026-05-12-a` PASS" (BACKPORT-DRAFT and SIBLING-DRAFT) | Local `swift --version` against each toolchain at `~/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-<date>.xctoolchain/usr/bin/swift` | Bundle IDs MATCH (`org.swift.64202603161a`, `…605071a`, `…605121a`) but version strings show: `2026-03-16-a` is **`Apple Swift version 6.4-dev`** (NOT 6.5-dev), `2026-05-07-a` is **`6.4-dev`** (NOT 6.5-dev), `2026-05-12-a` is `6.5-dev` ✓ | **CORRECTED** — REVIEWED-* outputs use neutral "swift.org main-branch nightly" framing with the specific Swift commit `cf0aed5b19d520f` cited where load-bearing |
| C-20 | swiftlang/swift#74303 is OPEN, DiscordBM, title contains "__swift_instantiateConcreteTypeFromMangledName" | `gh issue view 74303` | MATCH | KEEP |
| C-21 | swiftlang/swift#69615 is OPEN, "TypeLookupError for getTypeByMangledNameInContext" | `gh issue view 69615` | MATCH | KEEP |
| C-22 | swiftlang/swift#74333 is "closed dupe of #74303" | `gh issue view 74333` + reading the comment thread | `stateReason: COMPLETED` and the closure path is a fix in PR #74604 (per MarkVillacampa comment), not a duplicate-of resolution; another commenter on #74303 only **speculated** it might be the same issue | **CORRECTED** — REVIEWED-* outputs DROP the "closed dupe of #74303" claim. (The sibling-comment doesn't need to mention #74333 at all; the backport-request never did.) |
| C-23 | rdar://169536826 referenced by PR #87066 | `gh pr view 87066 --jq '.body'` | EXACT MATCH (PR body ends `rdar://169536826`) | KEEP |
| C-24 | Venue precedent #88239 ("title flags affected branch") | `gh issue view 88239` | EXISTS; title is `Serialized explicit module paths … on release/6.3` (branch-named in suffix, not bracketed prefix) — the precedent supports "title contains affected-branch identifier" but our chosen `[release/6.3] Backport request: …` prefix is a closely related convention rather than identical | KEEP with framing softened in REVIEWED-BACKPORT-REQUEST frontmatter |
| C-25 | PR #87066 body acknowledges "we also had the mangling and runtime type casting incorrect, or at least, untested for the -WithDefaults version until now" | `gh pr view 87066 --jq '.body'` | EXACT MATCH | KEEP in BACKPORT-REQUEST (dropped from SIBLING-COMMENT for length-budget reasons — readers can click through) |

### Section B — Workspace file:line citations

| ID | Claim | Verification method | Verified result | Action |
|----|-------|---------------------|-----------------|--------|
| C-26 | `swift-foundations/swift-executors/Sources/Executors/Kernel.Thread.Executor.Sharded.swift:46,57` carries `Atomic<Index<Kernel.Thread>>` | `Read` lines 40–60 | line 46: `private let cursor: CPU.Cache.Padded<Atomic<Index<Kernel.Thread>>>`; line 57: `self.cursor = .init(Atomic<Index<Kernel.Thread>>(.zero))` | KEEP (cited in BACKPORT-REQUEST's "Additional information" tail of the original draft; reviewed version trims production-impact list to keep the body terse — listed instead in `INVESTIGATION-ARC.md` for the click-through) |
| C-27 | `…/Kernel.Thread.Executor.Stealing.swift:57` carries `Atomic<Index<Kernel.Thread>>` | `Read` line 57 | `private let cursor: Atomic<Index<Kernel.Thread>>` | KEEP (same disposition as C-26) |
| C-28 | `…/swift-kernel/Sources/Kernel Event/Kernel.Event.Driver.swift:103` carries `Dictionary_Primitives.Dictionary<Kernel.Event.ID, Registration>` | `Read` line 103 | `var registry = Dictionary_Primitives.Dictionary<Kernel.Event.ID, Registration>()` | KEEP (same) |
| C-29 | `…/swift-io/Sources/IO Completions/Completion.Actor.swift:86` carries `Dictionary<Kernel.Completion.Token, Completion.Entry>` | `Read` line 86 | `private var entries: Dictionary<Kernel.Completion.Token, Completion.Entry> = .init()` (stdlib `Dictionary`) | KEEP (same) |
| C-30 | "~13 statements in `Sources/Reproducer/main.swift`" | `Read` the file (30 code lines) + manual count | **9 top-level items**: 4 `import` decls + 1 `enum SimpleTag` decl + 3 `let` bindings + 1 `print` call. The executable body proper is 5 statements (enum + 3 lets + print). "~13" is a loose overestimate either way. | **CORRECTED** — REVIEWED-* outputs use "9 statements", which matches the verbatim code block shown in both drafts so the reader can count it directly |

### Section C — CI cross-platform empirical data (run 26326702012)

| ID | Claim | Verification method | Verified result | Action |
|----|-------|---------------------|-----------------|--------|
| C-31 | macOS leg (job `77505668783`) CRASH | `gh run view --job 77505668783 --log` grep for signal/exit | `error: Process … exited with unexpected signal code 11`; toolchain path `/Applications/Xcode_26.4.1.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper`; build command `swift test -c debug`; macOS 26.4 / runner image `macos-26-arm64` | KEEP — INCORPORATED into REVIEWED-* |
| C-32 | Ubuntu Swift 6.3 release leg (job `77505668792`) NO CRASH | `gh run view --job 77505668792 --log` | `Swift version 6.3.2 (swift-6.3.2-RELEASE)`; build command `swift test -c release`; test output: `Test reproducer() recorded an issue at Reproducer.swift:40:23: Known issue was not recorded`; final state: `Process completed with exit code 1` (CI conclusion=failure, but failure is the `withKnownIssue`-not-fired SwiftTesting signal, not a SIGSEGV) | KEEP — INCORPORATED |
| C-33 | Ubuntu Swift main nightly leg (job `77505668805`) PASS | same | `Swift version 6.5-dev (LLVM 75d1da2e54728a4, Swift cf0aed5b19d520f)`; build command `swift test -c release`; test output: `✔ Test reproducer() passed after 0.001 seconds.` | KEEP — INCORPORATED |
| C-34 | Windows Swift 6.3 debug leg (job `77505668808`) AMBIGUOUS | `gh run view --job 77505668808 --log` | `Swift version 6.3.2 (swift-6.3.2-RELEASE)` from the swift.org cached toolchain `C:\hostedtoolcache\windows\swift-6.3.2-RELEASE-windows10\6.3.2\…`; build command `swift test -c debug`; test output: `◊ Test reproducer() started.` followed by `##[error]Process completed with exit code 1.` (no SwiftTesting summary, no signal-code metadata captured) | KEEP — INCORPORATED with the explicit "inconclusive" qualifier |

### Section D — Cross-platform claims in the original drafts

| ID | Claim (original) | Verification | Audit disposition |
|----|------------------|--------------|-------------------|
| C-35 | BACKPORT-DRAFT Environment row: "Platform | macOS 26.2 (build 25C56), arm64. Linux/Windows not yet verified empirically; the failure mode (runtime metadata demangler) is platform-independent so the same bug likely affects every host." | CI run 26326702012 (Section C) refutes the "platform-independent / affects every host" speculation: swift.org Linux 6.3.2 (same `swift-6.3.2-RELEASE` source tag) does not crash. | **REFUTED in part** — REVIEWED-BACKPORT-REQUEST replaces this row with the empirical CI matrix and qualifies the conclusion ("Apple Xcode 6.3.2 macOS arm64 debug crashes; swift.org Linux 6.3.2 x86_64 release does not, on the same source tag"). |
| C-36 | BACKPORT-DRAFT Description: "All currently shipping Apple Swift 6.3.x toolchains … carry the unfixed demangler." | CI run confirms macOS Xcode 6.3.2 crashes. The narrower claim is supportable; the broader implicit claim (uniform across every release/6.3-derived toolchain) is empirically refuted. | **NARROWED** — REVIEWED-BACKPORT-REQUEST scopes the failure to "Apple Xcode 6.3.x" specifically and surfaces the open question about whether the defect's locus is in `release/6.3` source or in Apple-downstream artifacts. |
| C-37 | Implicit hypothesis: bug locality | New empirical observation (macOS-crashes / Linux-doesn't / Windows-ambiguous under the same `swift-6.3.2-RELEASE` tag) suggests the defect may live in Apple-downstream toolchain artifacts (Synchronization framework binary, Apple-specific cherry-picks, build pipeline differences) rather than `release/6.3` source. | **SURFACED AS OPEN QUESTION** to release management in REVIEWED-BACKPORT-REQUEST's Ask section — surfaced rather than asserted. |
| C-38 | "both `-Onone` and `-O` reproduce on 6.3.x" (BACKPORT-DRAFT Environment last row) | Not independently verifiable from CI run 26326702012 alone — macOS leg only runs `-c debug`; Linux 6.3 leg only runs `-c release`. The platform-vs-build-mode discriminator is **not isolated** by current CI. Local-testing assertion is accepted from the catalog §A9 record. | **CONFOUND SURFACED** — REVIEWED-BACKPORT-REQUEST notes the matrix-design confound and qualifies the CI-only conclusion. Recommendation for follow-up if release management asks: add a `macOS (Swift 6.3, release)` + `Ubuntu (Swift 6.3, debug)` matrix leg to isolate. |

### Section E — SIBLING-COMMENT-DRAFT specific claims

| ID | Claim | Verification | Action |
|----|-------|--------------|--------|
| C-39 | The dense ~430-word "Identified-fix" paragraph compressing snapshot bisection narrative + PR-body quote + identification path | All facts within it independently verified (C-05, C-06, C-17, C-18, C-25). | **REWRITTEN** — REVIEWED-SIBLING-COMMENT collapses to a 4-sentence "Identified fix" paragraph (~85 words); snapshot-bisection narrative dropped (not load-bearing for #74303 readers; available via INVESTIGATION-ARC click-through); PR-body quote dropped (readers can click through). |
| C-40 | Toolchain matrix listing only "Apple Swift 6.3.2 RELEASE … CRASH" and three nightlies | The toolchain matrix understated coverage by omitting the CI cross-platform legs and labeled the nightlies inconsistently with their actual `swift --version` (per C-19). | **REPLACED** — REVIEWED-SIBLING-COMMENT carries a 3-row CI matrix derived from run 26326702012 with the Linux NO-CRASH leg as a load-bearing data point that narrows the failure domain. |

---

## Items NOT removed from REVIEWED outputs despite minimization pressure

- **Open question on Apple-downstream-vs-upstream locality**: load-bearing for release management to choose the right channel (upstream cherry-pick vs Apple Feedback Assistant). Surfacing — not asserting — is the right discipline given the confound noted at C-38.
- **`Tagged_Primitives.Tagged` production-symbol-load-bearing caveat (bare-`swiftc` reduction does not reproduce)**: load-bearing to explain why the reproducer is SwiftPM rather than single-file; without it the reproducer looks under-reduced.
- **lldb-pinned fault site (`__swift_instantiateConcreteTypeFromMangledNameV2` returning null)**: load-bearing for maintainers to scope the runtime entry point at issue.
- **`SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1` reachability marker**: a one-line check that lets a maintainer verify the failure mode on their own machine without lldb.

---

## Verification reproducibility

Every PASS in this audit is reproducible. The verification commands are:

```bash
# C-01..C-04, C-25
gh pr view 87066 --repo swiftlang/swift --json number,title,author,mergedAt,mergeCommit,baseRefName,state,body

# C-05..C-07, C-23
gh api repos/swiftlang/swift/commits/bc44d42f11830ea37a3b882e332ef480c1b4324e

# C-08, C-09
gh api repos/swiftlang/swift/pulls/87066/commits
gh pr view 87066 --repo swiftlang/swift --json files

# C-10, C-11, C-12
gh pr view 87066 --repo swiftlang/swift --json files --jq '{total_additions: ([.files[].additions] | add), total_deletions: ([.files[].deletions] | add), files: .files}'

# C-13, C-14, C-15
gh api repos/swiftlang/swift/compare/release/6.3...bc44d42f11830ea37a3b882e332ef480c1b4324e
gh api repos/swiftlang/swift/compare/release/6.3.1...bc44d42f11830ea37a3b882e332ef480c1b4324e
gh api repos/swiftlang/swift/compare/release/6.4.x...bc44d42f11830ea37a3b882e332ef480c1b4324e

# C-16
gh api repos/swiftlang/swift/git/refs/tags/swift-6.3.2-RELEASE

# C-17, C-18
gh api repos/swiftlang/swift/commits/4c5257d961
gh api repos/swiftlang/swift/commits/d13cbbfd33

# C-19 (run on macOS host with the snapshots installed)
~/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-03-16-a.xctoolchain/usr/bin/swift --version
~/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-05-07-a.xctoolchain/usr/bin/swift --version
~/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-05-12-a.xctoolchain/usr/bin/swift --version

# C-20, C-21, C-22, C-24
gh issue view 74303 --repo swiftlang/swift
gh issue view 69615 --repo swiftlang/swift
gh issue view 74333 --repo swiftlang/swift --json stateReason,comments
gh issue view 88239 --repo swiftlang/swift

# C-31..C-34
gh run view --repo swift-institute/Issues --job 77505668783 --log
gh run view --repo swift-institute/Issues --job 77505668792 --log
gh run view --repo swift-institute/Issues --job 77505668805 --log
gh run view --repo swift-institute/Issues --job 77505668808 --log
```

CI run URL (for the orchestrator's posting context): https://github.com/swift-institute/Issues/actions/runs/26326702012

---

## Recommended follow-ups (out of scope for this audit; for orchestrator consideration)

1. **Catalog correction**: `swift-institute/Research/swift-compiler-bug-catalog.md` §A9 update table labels three snapshots as "Swift 6.5-dev nightly". Empirically two are 6.4-dev (per C-19). The mislabel propagated from the catalog into the original drafts; corrections in REVIEWED-* outputs do not fix the source. Recommend a catalog amendment when next touched.
2. **CI matrix design**: add `macOS (Swift 6.3, release)` and/or `Ubuntu (Swift 6.3, debug)` legs to isolate the platform-vs-build-mode discriminator (per C-38). Not load-bearing for the post itself, but would strengthen any follow-up discussion with release management.
3. **CI run freshness**: if the reproducer's `d85cfcc` commit drifts before the orchestrator authorizes posting, trigger a fresh CI run and update the run-ID citation in the REVIEWED-* tables. Per the brief's "no posting / no commits / no pushes" boundary the audit cannot do this autonomously.
4. **Catalog cross-link**: §A9's "UPSTREAM FILING STATUS: NOT YET FILED" line will need updating to point at the posted issue numbers after orchestrator authorization + posting.
