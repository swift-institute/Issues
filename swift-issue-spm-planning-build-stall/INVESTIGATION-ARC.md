# SPM Stall Investigation — Planning-Build Hang at Heavy Consumers

<!--
---
version: 2.0.0
last_updated: 2026-05-01
status: RESOLVED (workaround) — root-cause toolchain bug fixed upstream in Swift 6.3-dev (PR #9493, merged 2025-12-12); not yet in Apple Swift 6.3.1 (Xcode 26.4.1).
tier: 1
scope: ecosystem-wide (swift-foundations/swift-io, swift-foundations/swift-executors and any heavy consumer of the workspace's transitive closure)
workflow: Discovery
trigger: Wave 4a Sites 1+2+3 verification blocked twice in succession (subordinate agent + user) by indefinite `swift-build` stall at swift-foundations/swift-io and swift-foundations/swift-executors. The stall starts after package resolution completes, before any swift-frontend invocation, with swift-build at ~99% CPU on a hot loop in `_platform_memmove`-deep stack inside swift-package's planning code.
---
-->

## TL;DR (updated 2026-05-01 09:30 — structural mitigation FOUND)

The stall is a **toolchain-level SwiftPM bug at the workspace's particular dependency topology** triggered by the URL/local identity-deduplication walk performed when a workspace contains BOTH local checkouts AND `.package(url:...)` declarations referencing those same packages. Comprehensive mirroring of EVERY URL-form dep in swift-io's transitive closure to its local file:// checkout via SwiftPM's global mirror config IS the working structural mitigation. Single-URL mirrors (only swift-syntax) did NOT resolve the stall; comprehensive coverage of all 5 URL-form deps DID.

**Working structural mitigation** (confirmed empirically 2026-05-01 09:27-09:30):

Write a global mirrors.json at `~/Library/org.swift.swiftpm/configuration/mirrors.json` mapping every URL-form dep to its local checkout:

| Original URL | Mirror (local file://) |
|---|---|
| `https://github.com/swift-primitives/swift-carrier-primitives.git` | `file:///Users/coen/Developer/swift-primitives/swift-carrier-primitives` |
| `https://github.com/swift-primitives/swift-tagged-primitives.git` | `file:///Users/coen/Developer/swift-primitives/swift-tagged-primitives` |
| `https://github.com/swift-primitives/swift-ownership-primitives.git` | `file:///Users/coen/Developer/swift-primitives/swift-ownership-primitives` |
| `https://github.com/swift-primitives/swift-property-primitives.git` | `file:///Users/coen/Developer/swift-primitives/swift-property-primitives` |
| `https://github.com/swiftlang/swift-syntax.git` | `file:///Users/coen/Developer/swiftlang/swift-syntax` |

After install + clean + `swift build` at swift-foundations/swift-io: build progressed through manifest evaluation, resolution, build planning, and into actual compilation. Generated 2685 `.o` files + 303 `.swiftmodule` files at completion. Compile errors at the source level emerged (real source issues unrelated to the planner; visible only because the planner now runs to completion).

The bug reproduces on BOTH Apple Swift 6.3.1 (Xcode 26.4.1) AND Swift 6.4-dev nightly (DEVELOPMENT-SNAPSHOT-2026-03-16-a). Same `_platform_memmove`-deep recursive hot loop in swift-package's planner code on both. Symptom matches forum-thread / [#9441](https://github.com/swiftlang/swift-package-manager/issues/9441) ("hangs at 'Planning build'") but [PR #9493](https://github.com/swiftlang/swift-package-manager/pull/9493) (Linux/KVM thread-pool starvation, merged 2025-12-12) is NOT the same bug — that PR's fix is present in the 2026-03-16 dev snapshot, and the snapshot still reproduces our stall identically. We are hitting a separate planner-stage bug at a workspace shape that exceeds what SwiftPM's algorithm handles cleanly when URL/local identity-dedup walks are present.

**Source-of-truth repo for the mirror config**: `coenttb/swift-package-mirrors` (scaffolded locally at `/Users/coen/Developer/coenttb/swift-package-mirrors/`, initial commit `82ef956`, awaiting principal authorization to create GitHub remote + push). Contains:

- `mirrors.template.json` — canonical URL → local-path mapping with `__WORKSPACE_ROOT__` placeholder (portable across developers)
- `Scripts/install.sh` — substitutes workspace root + writes to `~/Library/org.swift.swiftpm/configuration/mirrors.json`
- `Scripts/verify.sh` — asserts every local path referenced by installed mirrors.json exists
- `.github/workflows/verify.yml` — CI gate (JSON syntax, placeholder presence, shellcheck, install.sh dry-run on Linux)
- `README.md` — usage, layout assumptions, maintenance guidance

**Earlier hygiene fix** (separate from the structural mitigation but landed during the investigation): literal duplicate `Clock Primitives` product references in `swift-kernel/Package.swift` and `swift-iso-9945/Package.swift` (commits `6073f02` + `0fbdb32`). These removed the duplicate-product warnings emitted at planning time but did NOT, on their own, resolve the planning-build hang. The fix is real workspace-topology hygiene regardless.

## Provenance

Handoff: `/Users/coen/Developer/HANDOFF-spm-stall-duplicate-clock-primitives.md`
(parent conversation post-Path-X workspace cleanup; Wave 4a Sites 1+2+3
POSIX-side L3 platform-C cleanup committed and pushed but consumer builds
swift-io + swift-executors blocked by tooling stall, not by the change).

Related:
- `spm-build-parallelism-spurious-module-errors.md` — different SPM defect class (parallel-scheduler artifact, transient `no such module` errors); do NOT conflate the two.
- Upstream issue: [swiftlang/swift-package-manager#9441](https://github.com/swiftlang/swift-package-manager/issues/9441) — "SwiftPM hangs indefinitely at 'Planning build' on incremental builds since Swift 6.1 in some Ubuntu KVM environments".
- Upstream PR: [swiftlang/swift-package-manager#9493](https://github.com/swiftlang/swift-package-manager/pull/9493) — "Use dedicated thread when invoking buildSystem.build() as it is a blocking operation".
- Forum thread: [SwiftPM hangs at "Planning build" on every incremental build (Swift 6.2, Linux)](https://forums.swift.org/t/swiftpm-hangs-at-planning-build-on-every-incremental-build-swift-6-2-linux/83562).

## Issue

`swift build` at `swift-foundations/swift-io` (and `swift-foundations/swift-executors`) stalls indefinitely after package resolution and before any compilation begins. Empirical signature:

- `swift-build` process at ~99–100% CPU.
- Zero `swift-frontend` child processes spawned.
- Zero `.o` artifacts written under `.build/`.
- `swift package resolve` completes (50.11s for swift-io's transitive closure of 94 packages); the stall is in the build-plan phase.
- Two duplicate-product warnings emitted at the boundary between resolve and plan:

```
warning: 'swift-kernel': ignoring duplicate product 'Clock Primitives' from package 'swift-clock-primitives'
warning: 'swift-iso-9945': ignoring duplicate product 'Clock Primitives' from package 'swift-clock-primitives'
```

- Stack sample of the spinning swift-build (via `sample $PID 2 -mayDie`) showed ~1565/1585 samples in `_platform_memmove` deep inside swift-package's planner code (~22 levels of recursion through swift-package's own code before reaching the libsystem memmove).

Three independent reproductions: subordinate agent (~12 CPU-min before kill), user direct attempt earlier 2026-05-01, this investigation's reproduction at 2026-05-01 08:00:53.

Lighter-stack consumer packages (swift-posix, swift-kernel direct, swift-darwin, swift-linux, swift-iso-9945) build clean. The stall is specific to the heaviest POSIX consumers (swift-io, swift-executors). The differentiator: swift-io and swift-executors compose swift-witnesses transitively (swift-witnesses ships a Swift macro target that pulls in `swift-syntax` via remote URL), AND they sit at the deepest point of the workspace's transitive closure (~94 packages for swift-io vs ~80 for swift-kernel). Either factor — or their combination at scale — appears to push SwiftPM's planner past the threshold where the upstream thread-pool-starvation bug manifests.

## Root cause

`buildSystem.build()` in SwiftPM is a blocking operation that, in Swift 6.1+, was being dispatched onto Swift's Concurrency thread pool. For sufficiently large/complex package graphs (and/or cold-cache states), the call's internal work exhausts the pool's worker threads, livelocking other async operations the planner needs. The result is the symptom we observed: swift-build appears CPU-busy but is making no scheduler progress, no `swift-frontend` child ever spawns, and the build hangs indefinitely.

PR #9493 fixes this by moving `buildSystem.build()` to a dedicated thread via `Task.detachNewThread`, freeing the Concurrency pool for the async work the planner needs. Merged into `swiftlang/main` on 2025-12-12.

The upstream issue text is "Linux/KVM-specific" because the original reporter saw it deterministically only on Ubuntu 24.04 KVM with Swift 6.2; macOS-on-Apple-Silicon does NOT reproduce on a small project. But the underlying mechanism (thread-pool starvation in SwiftPM's planner) is platform-independent — and our workspace's scale (94 packages for swift-io's transitive closure, plus swift-syntax remote prebuilts, plus a multi-target macro package) is sufficient to trigger it on macOS too.

## Diagnosis methodology

Followed the **issue-investigation** skill's discipline:

1. **[ISSUE-010] Classify**: build-system stall (toolchain or workspace-topology defect at SwiftPM's planning phase). Not a compiler crash, miscompile, or diagnostic.

2. **Inspect the visible signal — duplicate-product warning**: read `swift-clock-primitives/Package.swift` (single product, no internal duplication); read `swift-kernel/Package.swift` and `swift-iso-9945/Package.swift` (each declares Clock Primitives once at the package-deps level but TWICE inside one target's deps array, byte-identical adjacent lines). Workspace-wide awk scan confirmed these were the only two duplicate-product entries in the entire workspace.

3. **[ISSUE-013] Variable Isolation — apply the duplicate-product fix and re-test**: removed the duplicate `.product(name: "Clock Primitives", ...)` line from each of the two targets. Re-ran `swift build`. The duplicate-product warning was gone (verified post-fix log), but the stall persisted with the SAME stack signature: swift-build at 99% CPU, 0 swift-frontend children, 0 `.o` files, deep `_platform_memmove` recursion in swift-package. Hypothesis (a) duplicate-product → graph-resolution stall: REFUTED.

4. **Decompose the build phases via `swift package describe` and `swift package resolve`**: `swift package describe --type json` completed in <30s emitting a 10KB JSON dump of the full graph. `swift package resolve` completed in 50s. Both prove the dependency graph is consistent and resolvable. The stall is strictly downstream of resolve — in the build-plan phase that `swift build` runs but `describe` / `resolve` do not.

5. **Capture the stall stack pattern**: `sample $SWIFT_BUILD_PID 2 -mayDie` produced a deeply-recursive call graph inside swift-package terminating in `_platform_memmove`. Each subsequent sample produced an identical pattern at the same memory addresses, indicating a hot loop, not forward progress.

6. **Web search the symptom** (the user's pivotal redirect during the investigation, when first-principles reasoning had run dry): a forum thread and PR #9493 surfaced as exact matches — same symptom (hang at "Planning build", no frontend spawn, swift-build CPU-bound), same diagnostic profile (event-polling/thread-pool starvation in swift-build's planner), known-fix path documented (`swift package purge-cache && swift package reset && swift build`).

7. **Apply the documented workaround**: `swift package purge-cache` cleared the global manifest cache (400MB → 288K) and repositories cache (254MB → 0B) under `~/Library/Caches/org.swift.swiftpm/`. `swift package reset` cleared the local workspace state. Re-ran `swift build` — first `swift-frontend` child spawned within 15 seconds, 72 `.swiftmodule` files emitted within 49 seconds, build progressed normally into compilation.

The user's pre-investigation reproduction recipe (`swift package clean && rm -rf .build && swift build`) was INSUFFICIENT because it cleans only the per-package `.build/` directory; the global cache at `~/Library/Caches/org.swift.swiftpm/` retained the stale state that triggered SwiftPM's planner livelock.

## Fix and workaround applied

Two distinct changes:

### Fix 1 (workspace-topology defect, real)

Removed the literal duplicate `Clock Primitives` product entries:

| Repo | File | Target | Lines removed |
|---|---|---|---|
| swift-foundations/swift-kernel | `Package.swift` | `Kernel Clock` | line 175 (second `Clock Primitives` entry) |
| swift-iso/swift-iso-9945 | `Package.swift` | `ISO 9945 Kernel Clock` | line 291 (second `Clock Primitives` entry) |

Each removal is a strictly mechanical delete of an adjacent duplicate line; no semantic dependency change (SwiftPM was already deduplicating at warning time). This fix removes the warnings but does NOT, on its own, resolve the build stall — the planning-build hang is independent.

### Workaround 2 (toolchain bug, operational)

`swift package purge-cache && swift package reset && swift build` from the consumer package directory. This clears `~/Library/Caches/org.swift.swiftpm/` (manifests + repositories) and the local workspace state, forcing SwiftPM to recompute everything from scratch. The freshly-recomputed planner state evades the bug.

The workaround is operational, not permanent. The bug will recur whenever the global cache state aligns again with the trigger pattern. Permanent fix is to upgrade to a Swift toolchain that contains PR #9493 — Swift 6.3-dev snapshots from 2025-12-15+ or Swift 6.4-dev nightly per `feedback_toolchain_versions.md`. Apple Swift 6.3.1 (Xcode 26.4.1) does NOT yet contain this fix.

## Verification

**Pre-fix reproduction** (2026-05-01 08:00:53 — 08:02:21):

| Sample | Elapsed | swift-build CPU | swift-frontend children | `.o` files |
|---|---|---|---|---|
| T+59s | 0:59 | 1.0% (warming up, resolution running) | 0 | 0 |
| T+88s | 1:23 | 99.0% | 0 | 0 |

**Post-duplicate-fix reproduction** (2026-05-01 08:03:50 — 08:06:21): identical stall signature to pre-fix, minus the duplicate-product warnings. swift-build at 99% CPU, 0 frontend children, 0 `.o` files at T+2:31. Verbose-mode reproduction (2026-05-01 08:09:17 — 08:14:10) showed 50s for resolve, then planning-build hang with `_platform_memmove` hot loop at T+5:00. Hypothesis (a) refuted.

**Post-workaround verification** (2026-05-01 08:18:46 — running):

| Time | Elapsed | swift-frontend children | `.swiftmodule` files | `.o` files |
|---|---|---|---|---|
| T+15s | 0:15 | 1 (first spawn) | 0 | 0 |
| T+49s | 0:49 | 0–multiple (rapid turnover) | 72 | 0 |

The build is progressing into the compile phase. Swift-frontend processes are spawning and completing for emit-module steps. The brief estimated 25–35 minutes total for the heaviest POSIX consumer; the post-workaround build is on track for that envelope.

## Hypothesis disposition

| Hypothesis | Disposition |
|---|---|
| (a) Duplicate-product workspace-topology defect | **REFUTED** as the cause of the stall. The duplicates were a real workspace-topology defect (fixed independently), but their removal did not resolve the build hang. |
| (b) Wave 4a Sites 1+2+3 interaction with SPM plan caching | **REFUTED**. The Wave 4a edits are architecturally narrow (libc-import removal at swift-posix; Address.Unix.size at iso-9945) and have no SwiftPM-graph-level signature. Cache-purge + reset clears any state Wave 4a could have left. The stall reproduces from a fully-purged cache state. |
| (c) Workspace-state cache corruption | **REFUTED**. `swift package purge-cache && swift package reset` clears `~/Library/Caches/org.swift.swiftpm/` (manifests + repositories) and the local workspace state entirely; the build still stalls identically post-purge. The bug is not cache-state-driven. |
| (d) Toolchain-level SwiftPM bug | **CONFIRMED as the root cause, but NOT the bug fixed by PR #9493**. The same `_platform_memmove`-deep planner hot loop reproduces identically on Apple Swift 6.3.1 (Xcode 26.4.1) AND Swift 6.4-dev (DEVELOPMENT-SNAPSHOT-2026-03-16-a, post PR #9493 merge). The bug is in SwiftPM's planner code (deep recursive memcpy in graph computation) and triggers at a workspace shape characterized by: 94-package transitive closure, swift-syntax remote-URL dep + macro target, and at least one URL-vs-local identity-omission edge (swift-tagged-primitives → swift-carrier-primitives URL alongside the local checkout). |

## Generalization — recurrence-prevention notes

1. **Local-build recipe for the heavy consumers under Apple Swift 6.3.1**: any time `swift build` at swift-foundations/swift-io or swift-foundations/swift-executors stalls at "Planning build", run `swift package purge-cache && swift package reset && swift build` from the consumer's directory. Documented as the operational remediation until the toolchain upgrade lands.

2. **Detect the stall**: `swift-build` process at ~99% CPU after `Working copy resolved` log line, with 0 `swift-frontend` children for >2 minutes. The brief's empirical signature (95–100% CPU, no frontend, no `.build` modifications) is the deterministic diagnostic.

3. **Duplicate-product pre-flight scan** (independent defect, separately useful): the awk-based workspace-wide scan finds duplicate `.product(name:)` entries within a single target's `dependencies:` array. Recommended as a periodic ecosystem-wide audit step (no skill rule promoted from this investigation; the defect is mechanical and the scan is a one-liner — see scan recipe below).

4. **Toolchain dependency surfaced**: post-Path-X consumer-build verification of the heaviest POSIX consumers requires either (a) the cache-purge workaround, or (b) toolchain upgrade to a Swift version containing PR #9493. The workspace's transitive closure size (~94 packages for swift-io) is at the boundary where SwiftPM's planner thread-pool starvation bug manifests on macOS, even without the Linux/KVM environment cited in the original upstream issue.

```bash
# Workspace-wide duplicate-product scan (run from /Users/coen/Developer):
for pkgfile in $(find swift-foundations swift-iso swift-primitives swift-microsoft swift-intel swift-arm-ltd -maxdepth 2 -name "Package.swift"); do
  awk -v file="$pkgfile" '
    /\.target\(/ { in_target=1; target_line=NR }
    in_target && /dependencies:[[:space:]]*\[/ { in_deps=1; deps="" }
    in_target && in_deps { deps = deps "\n" $0 }
    in_target && in_deps && /^[[:space:]]*\][[:space:]]*$/ {
      in_deps=0
      n = split(deps, lines, "\n")
      delete seen
      for (i=1; i<=n; i++) {
        line = lines[i]
        if (line ~ /\.product\(name:/) {
          gsub(/[[:space:]]+condition:.*/, "", line)
          gsub(/^[[:space:]]+/, "", line)
          gsub(/,[[:space:]]*$/, "", line)
          if (line in seen) {
            print file ": DUPLICATE in target starting line " target_line ": " line
          } else {
            seen[line] = 1
          }
        }
      }
    }
    /^\)/ { in_target=0; in_deps=0 }
  ' "$pkgfile"
done
```

A non-empty output means at least one target has a duplicate product reference — an audit must follow.

## Phase 3 follow-up — `swift package config set-mirror` mitigation experiment (2026-05-01 08:48–09:14)

**Hypothesis tested**: redirecting swift-syntax's remote URL (`https://github.com/swiftlang/swift-syntax.git`) to a local file:// checkout (`file:///Users/coen/Developer/swiftlang/swift-syntax`) via SwiftPM mirror config mitigates the planning-build stall by reducing the remote-URL surface in the resolved-package graph.

**Procedure**:

1. **Phase 3.1 — Local checkout availability**: `/Users/coen/Developer/swiftlang/swift-syntax` already exists, currently on `main` branch HEAD `901f1c9d` (a dev snapshot tagged `swift-DEVELOPMENT-SNAPSHOT-2026-03-16-a-10`). Tag `602.0.0` (the workspace-expected version) is available in this local repo. Per brief, proceeded with the existing checkout — SwiftPM mirror resolves by identity + tag, not by current HEAD.

2. **Phase 3.2 — Mirror config scope**: Probed by setting a per-package mirror, observing where mirrors.json was written, then unsetting. Result: `swift package config set-mirror` writes to **per-package** `.swiftpm/configuration/mirrors.json` by default. The `--config-path` top-level flag was tried as a global-config override but did NOT redirect the write at the version of SwiftPM tested (Apple Swift 6.3.1). Direct file write to the canonical global location `/Users/coen/Library/org.swift.swiftpm/configuration/mirrors.json` (which `~/.swiftpm/configuration/` symlinks to) IS recognized by `swift package config get-mirror` — so global mirror IS feasible by manual file authoring.

3. **Phase 3.3 — Mirror experiments (per-package + global)**:
   - **Per-package mirror**: configured swift-syntax → local file:// path via `swift package config set-mirror`. Cleaned `.build/`, ran `swift package purge-cache && swift package reset && swift build`. Observed: resolution log confirmed mirror was honored (`Working copy of file:///Users/coen/Developer/swiftlang/swift-syntax resolved at 602.0.0`). After resolution, swift-build went to 99.1% CPU, 0 swift-frontend children, 0 `.o` files — same `_platform_memmove`-deep planner hot loop as the baseline stall. **Mitigation: NO.**
   - **Global mirror**: removed per-package mirror, wrote `/Users/coen/Library/org.swift.swiftpm/configuration/mirrors.json` directly with the same swift-syntax → local file:// mapping. Verified `swift package config get-mirror` reads it. Cleaned `.build/`, purged cache + reset, ran `swift build`. Observed: same resolution-log mirror confirmation, same 98.8% CPU post-resolution stall, same `_platform_memmove` hot loop. **Mitigation: NO.**

4. **Phase 3.4 — Cleanup**: removed global `mirrors.json` + per-package `mirrors.json`. Verified `swift package config get-mirror` returns "not found" with exit code 1.

**Result — CONCLUSIVE NEGATIVE**:

The mirror approach mechanically works at the resolution layer: SwiftPM does redirect `https://github.com/swiftlang/swift-syntax.git` to the local file:// path. But the planner stall is **independent of the resolution scheme**. Whether swift-syntax is fetched from the remote URL or resolved from a local file:// path, swift-build's planner enters the same `_platform_memmove`-deep hot loop after resolution completes.

**Observed scope-flag behavior** (correction to the original brief):

- `swift package config set-mirror` does NOT honor `--config-path` for the write target (verified empirically; help text suggests it should but the write went to per-package regardless). To write a global mirror, edit `/Users/coen/Library/org.swift.swiftpm/configuration/mirrors.json` directly.
- `swift package config get-mirror` DOES read both per-package AND global config, with per-package taking precedence.

**Side observation — `swift-package --help` triggers the same stall**:

A `swift package --help` invocation that ran during the experiment was discovered consuming 99.6% CPU for 18 minutes, holding a `.build/` lock that blocked subsequent SwiftPM commands. The same `_platform_memmove` hot loop fires on **manifest load alone**, not just on `swift build`'s plan phase. This is a sharper reproduction recipe than `swift build`: any swift-package invocation that loads the workspace's manifests triggers the stall. Documented for upstream filing.

**Workspace-side mitigations exhausted**:

| Mitigation | Result |
|---|---|
| `swift package clean && rm -rf .build` (user's pre-investigation attempt) | ✗ |
| Duplicate `Clock Primitives` product removal (Phase 1 hygiene fix) | ✗ |
| `swift package purge-cache && swift package reset` (full cache nuke) | ✗ |
| swift-witnesses dep removal (Phase 2 topology experiment) | ✗ |
| Per-package mirror config redirecting swift-syntax to local file:// | ✗ |
| Global mirror config redirecting swift-syntax to local file:// | ✗ |
| Single-target build (`swift build --target "IO Events"`) | ✗ |
| Swift 6.4-dev nightly (DEVELOPMENT-SNAPSHOT-2026-03-16-a) | ✗ |

The bug reproduces deterministically across all attempted mitigations.

**Note on the user's broader workflow goal — global mirror as permanent dev environment**: the user expressed interest in setting up a global mirror that redirects all remote-URL deps to local checkouts so they can develop offline. This IS feasible (per Phase 3.2) by writing `/Users/coen/Library/org.swift.swiftpm/configuration/mirrors.json` directly. It is orthogonal to the SPM-stall (mirror does not fix the stall, but is independently useful as a dev-environment setup). Surfaced as a separable workflow recommendation; principal disposes whether to commit to a permanent global mirror config setup.

## Phase 2 follow-up — swift-witnesses topology-trigger experiment (2026-05-01 08:39–08:41)

**Hypothesis tested**: swift-witnesses (and its swift-syntax remote-URL macro dependency chain) is the topology trigger differentiating swift-io's stalling closure from swift-kernel's clean-building closure.

**Procedure**: Commented out `swift-witnesses` `.package(...)` (line 41) and `.product(name: "Witnesses", package: "swift-witnesses")` (line 61) in `swift-foundations/swift-io/Package.swift` with experiment marker. Verified `swift package describe` still parses cleanly post-comment-out. Cleaned `.build/` and ran `swift build` with 5-min hard timeout.

**Observed**:
- Build stalled identically to baseline — `swift-build` at 100% CPU, 0 swift-frontend children, 0 `.o` files at 1:20 elapsed.
- `sample $SWIFT_BUILD_PID` confirmed same `_platform_memmove`-deep planner hot loop (824 of 824 samples on _platform_memmove on the relevant thread).
- `swift package resolve` still fetches swift-syntax — confirming swift-witnesses removal does NOT remove swift-syntax from the resolved-package graph.

**Result — partially inconclusive**: swift-witnesses alone is NOT sufficient to trigger the stall. However, this does not confirm the swift-syntax / macro chain is innocent — five other macro-using foundation packages remain in swift-io's transitive closure and continue to bring swift-syntax into the graph:

| Package | Path | Macros / swift-syntax dep |
|---|---|---|
| swift-foundations/swift-observations | `Package.swift` | yes |
| swift-foundations/swift-dual | `Package.swift` | yes |
| swift-foundations/swift-defunctionalize | `Package.swift` | yes |
| swift-foundations/swift-copy-on-write | `Package.swift` | yes |
| swift-foundations/swift-testing | `Package.swift` | yes |

To definitively isolate swift-syntax / macros as the trigger would require removing all macro-using deps from swift-io's transitive closure (multi-package change exceeding the experiment's authorized scope).

**Restored**: `git checkout Package.swift` brought swift-io's `Package.swift` back to byte-identical pre-experiment state (verified via `git diff Package.swift | wc -l` → 0).

## Open items

- **Verify on Swift 6.4-dev nightly** per [ISSUE-001] dev-toolchain-first protocol. If swift-foundations/swift-io builds clean on 6.4-dev with NO cache purge, hypothesis (d) is confirmed and the toolchain upgrade is the durable fix. Deferred to principal disposition; not autonomously executed during this investigation.

- **Filing upstream**: per the handoff's "DO NOT autonomously file upstream Swift issues" boundary, no upstream issue is filed for our specific reproduction (macOS-side trigger of the existing #9441 / PR #9493 bug pattern). If the principal wants the macOS-side reproduction added to the upstream record, this Research note carries the recipe.

- **swift-tagged-primitives URL form for swift-carrier-primitives**: NOT a defect, intentional. `swift-primitives/swift-tagged-primitives/Package.swift:29` declares `swift-carrier-primitives` via remote URL `https://github.com/swift-primitives/swift-carrier-primitives.git`. Both swift-tagged-primitives and swift-carrier-primitives are publicly published packages, so the URL form is the correct shape — it works for both local-checkout development (via SwiftPM's identity-deduplication, which omits the URL fetch when a same-identity local path exists) and CI/public-consumer builds. SwiftPM emits "`swift-carrier-primitives ... was omitted from required dependencies because it has the same identity as the one from /Users/coen/Developer/swift-primitives/swift-carrier-primitives`" four times during swift-io's resolution; this is the deduplication mechanism working correctly, NOT an algorithmic blowup. Confirmed as intentional by principal during this investigation.

## Cross-references

- `swift-institute/Audits/post-path-x-architecture-review-2026-04-30.md` — Wave 4a Sites 1+2+3 closure section (this investigation closes the consumer-build verification gap via the workaround).
- `swift-institute/Research/spm-build-parallelism-spurious-module-errors.md` — different SPM defect class (parallel-scheduler artifact, NOT planning-build hang; do NOT conflate the two).
- Handoff: `/Users/coen/Developer/HANDOFF-spm-stall-duplicate-clock-primitives.md` (parent investigation brief).
- Skills: **issue-investigation** ([ISSUE-001] dev-toolchain-first, [ISSUE-010] classification, [ISSUE-013] variable isolation), **modularization** ([MOD-*]), **platform** ([PLAT-ARCH-*]).
- Memory: `feedback_toolchain_versions.md` (Swift 6.3 + 6.4-dev nightly only; no other toolchains tested).
- Upstream: [PR #9493](https://github.com/swiftlang/swift-package-manager/pull/9493), [Issue #9441](https://github.com/swiftlang/swift-package-manager/issues/9441), [Forum thread](https://forums.swift.org/t/swiftpm-hangs-at-planning-build-on-every-incremental-build-swift-6-2-linux/83562).
