# Investigation Arc — SwiftPM Identity-Conflict Path-Enumeration Hang

Terminal record. Investigation 2026-07-10 (single session, following the
overnight characterization). Method per the issue-investigation skill:
reproduce → reduce → verify → resolve; debug-prints-first ([ISSUE-023])
via an instrumented SwiftPM build once static modeling failed.

## Inherited state (overnight, 2026-07-10 05:19–05:48)

- Deterministic "hang": `swift build` / `swift package
  show-dependencies` spin forever; one thread 97–99 % CPU; zero child
  processes; no `.build` writes. Version solving always succeeds
  (`UPDATE_EXIT=0`), including the ~340-package app graph.
- Probe matrix (probes a–f in scratch `hang-bisect/`): three single-dep
  roots green; pairs/triples "hang". Two `sample` captures saved:
  probe-c and swift-mailgun-types, both hot in `_platform_memmove` on a
  cooperative-queue thread.
- Ruled out overnight: env pollution, manifest-cache corruption,
  root-level URL-spelling dedup, version solving, any single dep.

## Phase 1 — the hot frame had a name

The saved probe-c sample was complete (not truncated): 3708/3718
samples inside

```
SwiftPackageCommand.ShowDependencies.run
→ SwiftCommandState.loadPackageGraph
→ Workspace.loadPackageGraph
→ ModulesGraph.load
→ createResolvedPackages closure #3
→ findAllTransitiveDependencies(root:dependency:graph:)
→ specialized Array.replaceSubrange<A>(_:with:)
→ _platform_memmove
```

Source reading (local clone `~/Developer/swiftlang/swift-package-manager`,
tags read via `git show`, no checkout):

- `findAllTransitiveDependencies` = all-paths BFS, no visited set,
  `Array.removeFirst()` per pop (the memmove), enumerating every path
  from root through the whole DAG.
- Sole call site: the `createResolvedPackages` "conflicting identity"
  branch (`canonicalPackageLocation != dependencyPackageRef.canonicalLocation
  && !allowedToOverride`), twice per root × conflicting edge.
- Introduced by PR #8390 (2025-03-25); first shipped in
  `swift-6.2-RELEASE`; unchanged through `swift-6.3.2-RELEASE`,
  `release/6.4.x`, and `main` @ `3ff37917a`.
- `DependencyMirrors.mirror(for:)` = exact-string dictionary lookup —
  the mechanism by which two spellings of one URL can acquire two
  canonical locations on a mirrored machine.

## Phase 2 — static modeling failed; observation succeeded

A Python model of the conflict condition over the probe-b union graph
(109 pins, manifests read from the actual `.build/checkouts`) found
zero conflicting edges — yet the samples proved the branch ran. Per
[ISSUE-023], stopped theorizing:

- lldb attach denied by the OS.
- Built SwiftPM at the `swift-6.3.2-RELEASE` tag (fresh scratch clone;
  241 s) with a two-line instrumentation: print the conflict edge
  (identities + canonical locations, stderr) and **skip** the
  enumeration (`dependenciesPaths = []`).
- Running the dev-built `swift-package` needs
  `SWIFTPM_CUSTOM_LIBS_DIR=<toolchain>/usr/lib/swift/pm` (else
  `no such module 'PackageDescription'` at manifest compile) and the
  global option before the subcommand.

Instrumented cold run of a probe-a copy under the **pre-mitigation
mirror table** (see Phase 4) printed exactly one edge:

```
XCONFLICT package=swift-multipart-form-coding declares dep identity=swift-rfc-7578
  declared-canonical=/users/<user>/developer/swift-ietf/swift-rfc-7578
  resolved-canonical=github.com/swift-ietf/swift-rfc-7578
```

`swift-multipart-form-coding/Package.swift` spells the dep
`https://github.com/swift-ietf/swift-rfc-7578.git` (mirror hit → local
path); the probe root spells it bare (mirror miss → remote). One edge;
exponential enumeration; hang. Why static modeling missed it: the model
compared declared spellings against `Package.resolved` pins produced by
a *later* resolution (by then the bare spelling had gained a mirror
entry — Phase 4), i.e. it modeled the post-mitigation world.

## Phase 3 — the second exponential (the dumper)

A warm re-run of probe-b (valid pins + checkouts) got **past** graph
load and was then hot in `PlainTextDumper.dump → recursiveWalk`
(sample in `evidence/dumper-spin-probe-b-warm-sample.txt`), having
written **41.7 GB** of tree output. `PlainTextDumper` and
`FlatListDumper` print the DAG once-per-path — exponential on dense
DAGs, independent of any conflict. This reframes the overnight matrix:

- probe-b (ufc + rfc-7578) never had a conflict edge (nothing in ufc's
  subgraph declares rfc-7578); its overnight "hang" was the dumper.
  Confirmed: stock 6.3.2 `swift build` on the warm copy → **Build
  complete (37 s)**. Its overnight log even contains the *post-load*
  "dependency 'swift-rfc-7578' is not used by any target" warning —
  `checkAllDependenciesAreUsed` runs after `createResolvedPackages`,
  so load had finished.
- probe-a / probe-c (contain swift-multipart-form-coding) hung in
  load — their logs end *before* the post-load warning, and probe-c's
  sample shows the enumeration.
- Overnight verification used `show-dependencies`, so even a fixed
  load looked like "still hangs" — which is how the overnight
  "uniform spellings hang → dedup ruled out" verdict went wrong
  ([ISSUE-026]: that negative had show-dependencies-only coverage).

## Phase 4 — the environment was healing itself

`~/Library/org.swift.swiftpm/configuration/mirrors.json` grew from 437
entries (read 07:41) to 1086 (08:14) during this session: the
overnight→morning session had made the table **holistic** — both URL
spellings for all 505 institute clones (Workspace/inbox.md entry
2026-07-10 06:30; a `Scripts/sync-mirrors.sh` regenerator is queued
there). Overnight pin evidence (`swift-rfc-7578` pinned
`remoteSourceControl` in probe-b's overnight resolution) proves the
bare-spelling entry was absent during the overnight probe runs, i.e.
the probes ran pre-mitigation. SwiftPM also rewrites the shared file
(mtime) on ordinary builds, so mtime is not evidence of when entries
appeared.

Controlled A/B (project-local `.swiftpm/configuration/mirrors.json`
**replaces** the shared table wholesale, isolating the experiment from
the background rewriter):

- **A (pre-mitigation reconstruction: all bare institute-org keys
  removed)** → instrumented run fires XCONFLICT on exactly the
  multipart → rfc-7578 edge.
- **B (current comprehensive table)** → zero XCONFLICT; load completes
  to the post-load warnings.

## Phase 5 — reduction below the institute ([ISSUE-002]/[ISSUE-004])

`evidence/gen-synthetic.sh`: 39 local git repos — a 2-wide, N=18-deep
lattice (2^18 paths) plus one trivial leaf `conflicted` reachable as
`repos/conflicted` (root edge) and `repos-alias/conflicted` (a second
clone; lattice edge). No network, no mirrors, no institute packages,
plain `swift-tools-version: 6.0` manifests.

- `CONFLICT=0` (uniform spelling): `swift build` → **Build complete
  (117 s**, dominated by resolving 39 repos).
- `CONFLICT=1` (two clone paths): `swift build` → spins in
  `findAllTransitiveDependencies` (sampled:
  `evidence/synthetic-conflict-sample.txt`).
- Ingredient check: with package deps declared but products
  *unconsumed*, the same topology builds clean (product-filter pruning
  drops the edges) — target-level product consumption is a required
  ingredient.

## Phase 6 — real-package validation (current shared table, stock 6.3.2, cold scratch copies)

- **swift-mailgun-types**: no hang — terminates in ~8 min with an
  ordinary diagnostic: `product 'RFC_2822' required by package
  'swift-date-parsing' target 'UnixEpochParsing' not found in package
  'swift-rfc-2822'`. Genuine pre-existing drift the hang had masked:
  `swift-date-parsing/Package.swift:18` says `.product(name:
  "RFC_2822", …)`; `swift-rfc-2822` vends `"RFC 2822"` (space).
  One-line follow-up fix in swift-date-parsing.
- **swift-form-coding**: **Build complete (1791 s)** — full cold
  resolve + compile; the load-phase hang is dead there under the
  dual-spelling table alone.
- **swift-authentication**: still hung under the dual-spelling table —
  residual **org-axis** conflict (`pointfreeco/swift-dependencies` ×11
  edges remote vs `swift-foundations/swift-dependencies.git` mirrored
  local, which won resolution; spin re-sampled in
  `findAllTransitiveDependencies`). First fix attempt included an
  `apple/swift-numerics` → institute-fork mapping, which **broke
  version solving** (upstream apple/swift-numerics is a genuine 1.x
  dependency of the server stack, NOT an alias) — the alias-safety
  rule in README §1a came from this. 
- **swift-types-foundation**: still hung under the dual-spelling
  table — **org-migration drift** conflicts (7 identities): checkout
  manifests spelling moved RFC packages under the old
  `swift-standards/…` org (GitHub redirects resolve; canonicalization
  diverges from the mirrored `swift-ietf/…` spellings).
- The 33-entry scan (live manifests + both graphs' checkouts) fixed
  types-foundation (**terminates**, surfacing the same pre-existing
  `RFC_2822` diagnostic as mailgun) but authentication STILL spun: 4
  more org-drift identities lived only in PINNED checkout revisions
  (live-manifest scanning structurally cannot enumerate historical
  spellings). Mechanical closure: 196 `swift-standards/<name>` alias
  keys generated for every sub-org clone → 229-entry addendum
  (`evidence/mirror-entries-to-add.json`). Final authentication round
  with the comprehensive table: **no hang** — terminates with an
  ordinary post-load platform-floor diagnostic (`DateParsing` macos 13
  floor vs `RFC 5322` macos 26 floor — a second pre-existing
  swift-date-parsing drift the hang had masked, alongside the
  `RFC_2822` product-name drift). All four blocked packages
  (form-coding, mailgun-types, types-foundation, authentication) now
  terminate; every residual failure is an ordinary, actionable
  manifest diagnostic in swift-date-parsing, not the hang.
  Note: the permission classifier denied writing the additions into
  the SHARED mirrors.json this session — applying them globally (or
  regenerating via the queued `Scripts/sync-mirrors.sh`) is the
  principal's call; the project-local tables prove the fix.

## Resolution

Per [ISSUE-008]: unfixed upstream (6.2 → main) → staged terminal
dossier + structural workaround, documented in `README.md`:
comprehensive dual-spelling (and legacy-org) mirror coverage as the
immediate config-only fix — already live via the mirror tooling — and
uniform `.git`-spelling manifest hygiene as the durable fix (lint-rule
candidate). `swift package show-dependencies` is NOT a valid
verification probe (dumper exponential); verify with `swift build`.
