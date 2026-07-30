# Swift Issue: SwiftPM Identity-Conflict Path-Enumeration Hang (Graph Load)

> **Per-issue restructure: deferred (same ruling as
> [`swift-issue-spm-planning-build-stall/`](../swift-issue-spm-planning-build-stall/)).**
> The minimum reproducer is a multi-package SwiftPM workspace topology
> (two spellings of one package identity + a path-rich DAG), not a
> single-file Swift snippet, so the `Tests/` + `Sources/Reproducer/`
> two-target shape does not apply. The topology is fully scripted:
> [`evidence/gen-synthetic.sh`](evidence/gen-synthetic.sh) generates the
> whole reproducer offline (39 tiny local git repos, no network, no
> mirrors, no institute packages).

**Upstream destination**: `swiftlang/swift-package-manager` (adjudicated
2026-07-30 under Issues#69/#79: SwiftPM reproducers stay in this
repository; only the upstream target differs from the compiler entries).
**Upstream search (2026-07-30, swiftlang/swift-package-manager issues)**:
`findAllTransitiveDependencies` — 0 hits; "conflicting identity" — 3 hits
(#10054 folder-name identity conflicts, #8604 same-name dependencies
across owners, #8390 the PR that introduced the enumeration), none
reporting the exponential path-enumeration hang. **No match — ELIGIBLE
for upstream filing** (the scripted `evidence/gen-synthetic.sh` generator
is the minimal reproduction; filing itself remains principal-gated).
**Status**: root-caused; structural workaround validated and already
productionized (comprehensive dual-spelling mirror table); per-manifest
spelling hygiene is the durable fix.

---

## Characterization

**Classification**: Toolchain hang (accepts-valid topology, unbounded
computation — behaviorally an ICE-class blocker: `swift build` never
completes, no diagnostic, no progress).

**Environment**: Swift 6.3.2 release (`swift-6.3.2-RELEASE.xctoolchain`,
`TOOLCHAINS=org.swift.632202605101a`), macOS 26.5.1 arm64. The defective
code shipped first in **Swift 6.2** (PR swiftlang/swift-package-manager#8390,
merged 2025-03-25) and is still present on `main` (`3ff37917a`,
2026-07) and `release/6.4.x` — verified by source inspection of
`swift-6.2-RELEASE`, `swift-6.3-RELEASE`, `swift-6.3.1/2-RELEASE` tags.
Not fixed upstream; a dev-toolchain check cannot clear it ([ISSUE-001]
performed via tag/branch source audit).

**Command**: any command that loads the modules graph — `swift build`,
`swift package show-dependencies`, etc.

**Observed**: one thread at 97–99 % CPU inside
`ModulesGraph.load → createResolvedPackages → closure #3 →
findAllTransitiveDependencies(root:dependency:graph:)`, hot in
`Array.replaceSubrange → _platform_memmove` (i.e. `Array.removeFirst`
on the BFS work queue). Zero child processes, zero `.build` writes, no
log output. Never completes on institute-scale graphs (~110–340
packages).

**Expected**: graph load in seconds; at worst the pre-existing
"conflicting identity … will be escalated to an error" warning.

## Root Cause

Two SwiftPM defects compose:

### 1. Trigger — canonical-location conflict for one identity

`createResolvedPackages`
(`Sources/PackageGraph/ModulesGraph+Loading.swift`, identical logic at
tags `swift-6.2-RELEASE` through `swift-6.3.2-RELEASE`, lines ~455–470
at 6.3.2) compares, for every dependency edge:

```swift
if resolvedPackage.package.manifest.canonicalPackageLocation != dependencyPackageRef.canonicalLocation
    && !resolvedPackage.allowedToOverride
```

Any package identity that is *declared* under one canonical location by
one manifest but *resolved* under another enters this diagnostic branch.

In this workspace the divergence is produced by
`~/Library/org.swift.swiftpm/configuration/mirrors.json`:
`DependencyMirrors.mirror(for:)` is an **exact-string dictionary
lookup** (`Sources/PackageGraph/DependencyMirrors.swift`), so
`https://github.com/swift-ietf/swift-rfc-7578.git` (mirrored → local
path, canonical `/users/<user>/developer/swift-ietf/swift-rfc-7578`) and
`https://github.com/swift-ietf/swift-rfc-7578` (bare — misses the
mirror, stays remote, canonical `github.com/swift-ietf/swift-rfc-7578`)
are **different canonical locations for the same identity**. Without
mirrors both spellings canonicalize identically (canonicalization strips
`.git`), which is why CI and stock upstream users rarely trip this.
The same divergence also arises mirror-free from org-rename spellings
(`pointfreeco/swift-url-routing` vs
`swift-foundations/swift-url-routing`) and, in the synthetic
reproducer, from two clones of one repo.

### 2. Severity — all-paths BFS with no visited set

Since PR #8390 the branch calls (twice, per root package, per
conflicting edge):

```swift
private func findAllTransitiveDependencies(root:dependency:graph:)
    // BFS work queue of (node, pathToNode)
    while !queue.isEmpty {
        let currentItem = queue.removeFirst()          // O(queue) memmove per pop
        ...
        for dependency in edges[current] ?? [] {
            queue.append((dependency, pathToCurrent + [current]))   // every distinct path
        }
    }
```

No visited set, no memoization, no termination at the target: it
enumerates **every distinct path from the root through the entire
dependency DAG**, popping with `Array.removeFirst` (O(n) memmove each).
Path count in a dense layered DAG is exponential in depth (the
institute's shared-primitives graphs measure hundreds of packages, ~20
levels deep, heavy sharing → ≥ 2^N paths). The enumeration is
effectively non-terminating; the process shows the sampled
`_platform_memmove` spin.

**One conflicting edge suffices.** Instrumented 6.3.2 build (probe A,
pre-mitigation mirror table) printed exactly one conflict before the
enumeration would have started:

```
XCONFLICT package=swift-multipart-form-coding declares dep identity=swift-rfc-7578
  declared-canonical=/users/<user>/developer/swift-ietf/swift-rfc-7578
  declared-location=~/Developer/swift-ietf/swift-rfc-7578
  resolved-canonical=github.com/swift-ietf/swift-rfc-7578
  resolved-location=https://github.com/swift-ietf/swift-rfc-7578
```

(`evidence/instrumented-xconflict-line.txt`; instrumentation = print +
skip-enumeration patch on the `swift-6.3.2-RELEASE` tag.)

### Related but distinct — exponential `show-dependencies` dumpers

`PlainTextDumper` / `FlatListDumper.recursiveWalk`
(`Sources/Commands/Utilities/DependenciesSerializer.swift`) print the
dependency DAG as a **tree**, i.e. once per path — also exponential on
dense DAGs, *independent of any identity conflict*. A conflict-free
probe-b run got past graph load and wrote **41.7 GB** of tree output
without finishing (`evidence/dumper-spin-probe-b-warm-sample.txt`).
Consequence: `swift package show-dependencies` is unusable as a
verification command on institute-scale graphs and **must not be used
as the hang-probe** — it hangs for a second, unrelated reason after the
load-phase hang is fixed. Use `swift build` (or any non-dumping graph
load) to verify.

## Minimal Graph Shape

Required ingredients ([ISSUE-004]; removing any one makes it pass):

1. **Two canonical locations for one package identity**, at least one
   declared by a *non-root* manifest whose product is actually consumed
   (product-filter pruning removes unconsumed edges — verified: the
   same topology with unconsumed deps loads clean).
2. **A path-rich subgraph reachable from the root** (2-wide layered
   lattice of depth N ⇒ 2^N paths; N=18 is thoroughly sufficient).
   The conflicted package itself can be a trivial leaf; the lattice
   need not contain it.
3. Nothing else: no mirrors, no network, no branch-vs-version mix, no
   traits, no platform floors (synthetic uses plain
   `swift-tools-version: 6.0` manifests and local-path git deps).

`evidence/gen-synthetic.sh` generates both variants:
`CONFLICT=1` (same identity via two clone paths) hangs in
`findAllTransitiveDependencies`; `CONFLICT=0` (single spelling) builds
in seconds. See the validation matrix.

## Why the probe matrix looked like "any pair hangs"

The overnight probe matrix conflated the two exponential walks:

| Probe | Deps | Conflict edge present? | Actual hang site |
|---|---|---|---|
| e (rfc-7578 alone) | 1 | no (nothing else declares it) | none — green |
| f (url-form-coding alone) | 1 | no | none — green |
| d (swift-dependencies alone) | 1 | no | none — green |
| b (ufc + rfc-7578) | 2 | **no** (ufc subgraph never declares rfc-7578) | **dumper only** — `swift build` succeeds (37 s, validated) |
| a (multipart + rfc-7578) | 2 | **yes** (multipart declares `…rfc-7578.git` → mirror/local; root declares bare → remote) | **graph load** |
| c (ufc + multipart + rfc-7578) | 3 | yes (same edge) | graph load (sampled: `evidence/load-phase-spin-probe-c-sample.txt`) |
| swift-mailgun-types (real) | — | yes (pre-mitigation table) | graph load (sampled: `evidence/load-phase-spin-mailgun-sample.txt`) |

"Version solving always succeeds (UPDATE_EXIT=0)" is consistent:
resolution never touches `createResolvedPackages`; the conflict branch
runs at modules-graph load.

## Workaround (validated)

**Principle: make every spelling of an institute identity map to the
same canonical location.** Two layers:

1. **Mirror-table completion (config-only, no manifest edits, effective
   immediately).** For every mirrored package, carry BOTH URL spellings
   (`….git` and bare) — and any legacy-org spellings
   (`pointfreeco/…`, `coenttb/…`) — as mirror keys pointing at the same
   local path. The overnight→morning session already made the shared
   table holistic (Workspace/inbox.md 2026-07-10 06:30: both URL
   spellings for all 505 institute clones — 1086 entries, observed in
   effect by 08:14); validation below ran against that table. A
   `Scripts/sync-mirrors.sh` regenerator is queued (same inbox entry)
   to keep the dual-spelling invariant mechanical; 8 keys were still
   single-spelling as of this session (`apple/swift-argument-parser`,
   `swiftlang/swift-foundation`, six Standards sub-org packages) — no
   live manifest declares them bare today, but the regenerator should
   close them.
   A project-local `.swiftpm/configuration/mirrors.json` **replaces**
   the shared table wholesale (`Workspace+Configuration.swift`:
   "prefer local mirrors to shared ones"), which is how the
   pre-mitigation state was reconstructed for the A/B proof.
1a. **The org axis needs the same treatment (residual conflict found
   during validation).** swift-authentication's cold build still hung
   under the holistic dual-spelling table: its graph declares identity
   `swift-dependencies` under BOTH `pointfreeco/swift-dependencies`
   (11 edges, unmirrored → remote canonical) and
   `swift-foundations/swift-dependencies.git` (mirrored → local path,
   which won resolution) — an org-axis conflict the `.git`/bare fix
   cannot touch. Sampled spin confirmed `findAllTransitiveDependencies`.
   Ecosystem scan found four identities declared under both a legacy
   org and an institute org WITHOUT legacy-org mirror keys:
   `pointfreeco/swift-dependencies`, `coenttb/swift-html`,
   `apple/swift-numerics`, `coenttb/swift-translating` (the pattern is
   already established for url-routing/translating/server-foundation/
   stripe-types/urlrequest-handler/structured-queries-postgres). The
   **Alias-safety rule (learned the hard way)**: a legacy-org mirror
   entry is only correct when the legacy spelling is a TRUE ALIAS of
   the institute fork (fork carries the tags consumers pin —
   url-routing precedent). `apple/swift-numerics` is NOT an alias: it
   is a genuine upstream dependency of the server stack
   (async-http-client requires 1.x), and mapping it to the institute
   fork broke version solving ("no versions of 'swift-numerics' match
   the requirement 1.0.0..<2.0.0"). Same-identity-but-different-package
   pairs (`apple/swift-numerics` vs `swift-foundations/swift-numerics`)
   cannot be mirror-fixed — any graph containing both spellings is
   semantically broken (SwiftPM unifies them by identity) and must be
   fixed manifest-side. The remaining 6 entries (swift-dependencies,
   swift-html, swift-translating — all true-alias heritage forks) are
   staged in
   [`evidence/mirror-entries-to-add.json`](evidence/mirror-entries-to-add.json)
   — **applying them to the shared mirrors.json needs the principal**
   (the permission classifier denied the global write this session;
   validation used a project-local merged table instead, which SwiftPM
   prefers wholesale over the shared one). The queued
   `Scripts/sync-mirrors.sh` regenerator should emit legacy-org
   spellings for every heritage package so this class stays closed.
1b. **Third axis — institute org-migration drift.**
   swift-types-foundation's cold build exposed a further conflict
   class: pinned/checkout manifests that still spell moved packages
   under their OLD org home — `swift-standards/swift-rfc-{1123, 2822,
   3986, 5321, 5322, 6531, 6570, …}`, `swift-standards/swift-incits-4-1986`
   — which GitHub redirects resolve fine remotely but which have no
   mirror keys, so their canonical locations diverge from the
   `swift-ietf/…` (mirrored, local) spellings of the same identities
   (7 conflicting identities in that one graph, found by the static
   conflict model). These are true aliases (same repo, moved org).
   **Live-manifest scanning cannot close this class**: the conflicting
   spellings live in PINNED revisions (branch pins lag mirror HEADs;
   version pins are historical tags) — a second round surfaced 4 more
   drift identities (`swift-standards/{swift-ieee-754, swift-iso-9899,
   swift-rfc-4648, swift-whatwg-url}`) declared only by pinned
   checkouts. The mechanical closure is org-level: for EVERY package
   now under a per-authority sub-org, add
   `https://github.com/swift-standards/<name>` (+`.git`) alias keys →
   its local clone. The complete staged addendum is **229 entries**
   (196 historical `swift-standards/*` aliases for all sub-org clones
   + 18 observed drift spellings + 6 legacy-org true-alias spellings +
   9 bare complements for `.git`-only keys):
   [`evidence/mirror-entries-to-add.json`](evidence/mirror-entries-to-add.json).
2. **Spelling hygiene (durable, per-manifest).** Institute manifests
   MUST spell git dependencies uniformly — canonical institute-org URL
   **with** `.git` (matching the mirror-key convention). Bare spellings
   found in blocked-package manifests: `swift-form-coding`
   (`swift-ietf/swift-rfc-7578`), `swift-types-foundation`
   (`swift-ietf/swift-rfc-7578`, `swift-standards/swift-domain-standard`,
   `swift-standards/swift-emailaddress-standard`, plus four
   `pointfreeco/*` legacy spellings), `swift-mailgun-types`
   (`pointfreeco/swift-case-paths` — harmless while unmirrored, since
   both spellings then canonicalize identically, but it becomes a hang
   trigger the moment either spelling gains a mirror entry).
   Lint-rule candidate: flag any `.package(url:)` whose spelling is not
   the canonical `.git` form.

**Anti-recipe**: do NOT verify with `swift package show-dependencies` —
its dumper hangs exponentially on these graphs regardless of the fix.
Verify with `swift build`.

### Validation matrix

| Experiment | Mirror table | Command | Result |
|---|---|---|---|
| probe A (multipart+rfc-7578), instrumented 6.3.2, cold | pre-mitigation (bare institute entries removed, project-local) | show-dependencies (instrumented: print+skip) | **XCONFLICT fires** — 1 edge, exactly `swift-multipart-form-coding → swift-rfc-7578` |
| probe A, instrumented, cold | current comprehensive (project-local copy) | show-dependencies (instrumented) | **zero XCONFLICT**, load completes to the post-load warning |
| probe b (ufc+rfc-7578), stock 6.3.2, warm | current | `swift build` | **Build complete (37 s)** — same manifest that "hung" overnight |
| synthetic CONFLICT=1 (N=18, no mirrors, no institute pkgs) | n/a (inert local table) | `swift build` | **hangs in `findAllTransitiveDependencies`** (sampled; killed after cap) |
| synthetic CONFLICT=0 (N=18) | n/a | `swift build` | **Build complete** in seconds |
| swift-mailgun-types (real blocked pkg, scratch copy), stock 6.3.2, cold | current shared | `swift build` | **no hang** — terminates in ~8 min with an ordinary graph diagnostic (`product 'RFC_2822' … not found in package 'swift-rfc-2822'`) that the hang had been masking: `swift-date-parsing/Package.swift:18` names the product `"RFC_2822"`, `swift-rfc-2822` vends `"RFC 2822"`; one-line follow-up fix in swift-date-parsing |
| swift-form-coding (scratch copy), stock 6.3.2, cold | current shared | `swift build` | **Build complete (1791 s)** — full cold resolve + compile of the whole graph; manifest still spells rfc-7578 bare, absorbed by the dual-spelling table |
| swift-authentication (scratch copy), stock 6.3.2, cold | current shared (dual-spelling only) | `swift build` | **still hangs** — residual org-axis conflict: identity `swift-dependencies` declared under both `pointfreeco/…` (unmirrored, remote) and `swift-foundations/….git` (mirrored, local, wins resolution); spin re-sampled in `findAllTransitiveDependencies` |
| swift-authentication (scratch copy), stock 6.3.2, cold | shared + legacy-org entries incl. `apple/swift-numerics` | `swift build` | **no hang, but resolution fails** — the numerics mapping is wrong (genuine upstream, not an alias): "no versions of 'swift-numerics' match the requirement 1.0.0..<2.0.0"; entry withdrawn, alias-safety rule added |
| swift-authentication (scratch copy), stock 6.3.2, cold | shared + 33 alias entries | `swift build` | **still conflicts** — 4 more org-drift identities in pinned checkout manifests (`swift-standards/{swift-ieee-754, swift-iso-9899, swift-rfc-4648, swift-whatwg-url}`); spin sampled, edges enumerated statically |
| swift-authentication (scratch copy), stock 6.3.2, cold | shared **+ 229-entry comprehensive alias addendum** (project-local) | `swift build` | **no hang** — terminates with an ordinary post-load diagnostic (`'DateParsing' requires macos 13.0, but depends on 'RFC 5322' which requires macos 26.0` — pre-existing swift-date-parsing platform-floor drift, previously masked) |
| swift-types-foundation (scratch copy), stock 6.3.2, cold | current shared (dual-spelling only) | `swift build` | **still hangs** — org-migration-drift conflicts (7 identities: old `swift-standards/…` spellings of moved RFC packages in pinned checkout manifests); spin sampled in `findAllTransitiveDependencies` |
| swift-types-foundation (scratch copy), stock 6.3.2, cold | shared **+ 33 alias entries** (project-local) | `swift build` | **no hang** — terminates with the same ordinary `RFC_2822` product-name diagnostic as mailgun-types (pre-existing swift-date-parsing manifest drift, now surfaced instead of masked) |

## Duplicate Differentiation

- [swiftlang/swift-package-manager#8390](https://github.com/swiftlang/swift-package-manager/pull/8390)
  — the PR that *introduced* `findAllTransitiveDependencies` ("Provide
  context necessary to resolve identity conflict", 2025-03-25). Not a
  report of this hang.
- [swiftlang/swift-package-manager#8102](https://github.com/swiftlang/swift-package-manager/issues/8102)
  — `show-dependencies` slow since Xcode 16; undiagnosed; predates
  #8390, likely the dumper wall, not the conflict enumeration.
- [swiftlang/swift-package-manager#5940](https://github.com/swiftlang/swift-package-manager/issues/5940)
  and the Swift Forums thread on "same identity 'swift-protobuf'" — the
  same *conflict branch*, but pre-#8390 (diagnostic quality complaints;
  no unbounded enumeration).
- [`../swift-issue-spm-planning-build-stall/`](../swift-issue-spm-planning-build-stall/)
  — sibling institute record (2026-05): also URL/local identity-dedup
  topology, also `_platform_memmove`-deep spin, but in the *planning*
  stage and mitigated by comprehensive mirroring; this record is the
  *load-stage* exponential with an identified function and shape.
- No upstream issue found reporting the exponential behavior of
  `findAllTransitiveDependencies` (searched 2026-07-10; re-searched
  2026-07-30 — still no match, see the status block).

**Upstream fix shape (for reference only — not filed)**: memoized
reachability / visited set (or Deque) in
`findAllTransitiveDependencies`; the function only needs *one* path per
(root, dependency) pair for its diagnostic, so a parent-pointer BFS
producing a single shortest chain would be O(V+E).

## Evidence

| File | What it shows |
|---|---|
| `evidence/load-phase-spin-probe-c-sample.txt` | 10 s `sample` of stock 6.3.2 `swift-package` hot in `findAllTransitiveDependencies` → `Array.replaceSubrange` → `_platform_memmove` (99.7 % of samples), under `ShowDependencies.run → loadPackageGraph → createResolvedPackages closure #3` |
| `evidence/load-phase-spin-mailgun-sample.txt` | same hot stack on the real blocked package, under `SwiftBuildCommand.run` — proof that `swift build` (not just show-dependencies) hangs in load |
| `evidence/dumper-spin-probe-b-warm-sample.txt` | the *other* exponential: `PlainTextDumper.recursiveWalk` recursion, 41.7 GB written |
| `evidence/instrumented-xconflict-line.txt` | the single conflicting edge, printed by the instrumented 6.3.2 build |
| `evidence/gen-synthetic.sh` | offline synthetic reproducer generator (CONFLICT=0/1 A/B) |
| `evidence/synthetic-conflict-sample.txt` | sample of the synthetic hang (no institute packages, no mirrors) |
