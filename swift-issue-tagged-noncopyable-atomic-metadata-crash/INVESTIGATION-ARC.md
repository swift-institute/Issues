# Investigation Arc: Tagged + Atomic + `~Copyable` Runtime Metadata SIGSEGV

This document carries forward the four-arc convergence record. The
canonical bug-catalog entry for this defect is
`swift-institute/Research/swift-compiler-bug-catalog.md` §A9 (commit
`ba4b911`). The workspace-side investigation handoffs that produced this
record are `HANDOFF-test-sigsegv-post-cycle-break.md` (Arcs 1–3) and
`HANDOFF-tagged-noncopyable-atomic-metadata-crash.md` (Arc 4).

---

## Symptom

`swift test` in `swift-executors`, `swift-threads`, `swift-io` exits with
signal 11 (SIGSEGV) on Apple Swift 6.3.2 (Xcode 26.4.1). The test
process starts, runs ~20+ tests successfully, then segfaults mid-run.
The final test summary never prints; the suite is killed by the OS.

Reduction (per [`ISSUE-013`]) pinpointed the failing shape as
`Atomic<Tagged<Tag, Ordinal>>.advance(within: Tagged<Tag, Cardinal>)`
— the generic extension method declared at
`swift-ordinal-primitives/Sources/Ordinal Primitives Standard Library Integration/Atomic+Ordinal.swift:44`.

The runtime call `__swift_instantiateConcreteTypeFromMangledNameV2`
returns null when asked to instantiate the type metadata for
`Synchronization.Atomic<Tagged_Primitives.Tagged<Tag, Ordinal_Primitive.Ordinal>>`.
The caller's generated code stores the null result and passes it as the
first generic-metadata argument to `advance(within:)`; the function's
prologue dereferences `[x1 + 0x10]` (loading the metadata's first
generic-arg slot) and faults at virtual address `0x10`.

---

## Arc 1 (2026-05-22) — Category A identification, Shape A1 refuted

The first dispatch under the [`ISSUE-*`] investigation skill ran the
variable-isolation matrix (per [`ISSUE-013`]) and pinpointed the runtime
failure inside `libswiftCore.dylib!swift_getTypeByMangledName` returning
`TypeLookupError("unknown error")`. The classification at the time
(Category A — Tagged conditional conformance witness lookup,
early-resolution variant) led to a structural-fix recommendation: drop
the `Tag: ~Copyable` clause from `extension Tagged: AtomicRepresentable`
in
`swift-tagged-primitives/Sources/Tagged Primitives Standard Library Integration/Tagged+AtomicRepresentable.swift`.

Empirically refuted: applying the single-clause change had no effect on
the crash. The Category A hypothesis (conformance with `~Copyable` Tag
suppression triggers the demangler path that fails) was incorrect — or
at least incomplete. The `Tag: ~Copyable` clause is not the trigger.

---

## Arc 2 (2026-05-23 morning) — Typed-wrapper pivot landed and reverted

A subordinate pivoted to typed-surface wrappers over bare-`Underlying`
storage in four consumer repos:

| Repo | Workaround commit | Revert commit |
|------|-------------------|---------------|
| swift-primitives/swift-ordinal-primitives | `88780ee` (`Ordinal.AtomicPosition<Tag>`) | `e46b3b7` |
| swift-foundations/swift-executors | `dd34b04` (`Stealing.cursor`/`Sharded.cursor` switch) | `106d914` |
| swift-foundations/swift-kernel | `a79ca49` (`Kernel.Event.Driver` registry) | `44ab1f8` |
| swift-foundations/swift-io | `7c3c6207` (`Completion.Actor.entries`) | `b77a4f03` |

The workaround pattern: containers hold the Tagged's bare `Underlying`
raw value (UInt / UInt64) internally; the public surface accepts and
returns `Tagged<Tag, …>` so the phantom-Tag domain discipline carries
through. Test runs against this state went green (33/33 swift-executors,
22/22 swift-threads, 61/61 swift-io).

Orchestrator rejected the pivot: the typed-wrapper pattern degrades the
typed approach at the storage layer rather than fixing the cause; saving
the typed-surface form at the public API does not redeem dropping the
typed phantom-Tag from the storage. Per the memory entry
`feedback_correctness_and_evergreen.md`, structural correctness +
evergreen disposition outweigh consumer-demand thresholds (the memory
itself flags the relevant skill-side framing for future skill-lifecycle
rethink).
All four workarounds were reverted.

Catalog §A9 (commit `ba4b911`) was retained because the bug remained
real, only the proposed Institute-side fix was unsuitable.

---

## Arc 3 (2026-05-23 afternoon) — Tagged.swift single-file bisection exhausted

A subordinate bisected `Tagged.swift` directly under a single-file-edit
constraint, testing nine candidates derived from the orchestrator's
list of structural elements that might be the runtime trigger:

| # | Candidate | Result |
|---|-----------|--------|
| C1 | Remove `@frozen` from `Tagged` struct | **CRASH** |
| C2 | Remove `@_lifetime(copy underlying)` from `init(_unchecked:)` | NOT-RELEVANT (compiler rejects — required for `~Escapable` storage) |
| C3 | `public package(set) var underlying` → plain `public var` | **CRASH** |
| C4 | Drop `& ~Escapable` from `Tag` generic parameter | NOT-RELEVANT (cascades to sibling file) |
| C5 | Drop `& ~Escapable` from `Underlying` generic parameter | NOT-RELEVANT (cascades to sibling file) |
| C6 | Drop `, ~Escapable` from struct's own suppression | **CRASH** |
| C7 | Comment out all six optional stdlib conformances | **CRASH** |
| C8 | Move `AtomicRepresentable` conformance into `Tagged.swift` (inline) | **CRASH** |
| C9 | Comment out `extension Tagged where … { package mutating func modify… }` | **CRASH** |

Six testable candidates all left the crash intact. Conclusion: no
single-file edit to `Tagged.swift` resolves the runtime defect.
Combined with the earlier finding that a local wrapper mirroring
Tagged's exact declaration shape (`~Copyable & ~Escapable`, all
conditional conformances) does NOT reproduce, the trigger is something
specific to the production `Tagged_Primitives.Tagged` symbol's
materialization — not to its declaration shape, not to the
`Tag: ~Copyable` conformance suppression, not to the SLI submodule
home of the conformance.

Per the orchestrator's escalation rule, the dispatch returned with
three options (multi-file bisection, bare-`swiftc` reduction + upstream
filing, restore the typed-wrapper consumer fixes) and zero new commits.

---

## Arc 4 (2026-05-23) — Bare-`swiftc` not achievable; bug fixed on 6.5-dev

This dispatch applied the [`ISSUE-*`] skill in order with the explicit
goal of producing a bare-`swiftc` standalone reproducer and staging it
under the per-issue convention. The execution path was:

### [`ISSUE-001`] Dev-toolchain check

The brief noted that Swift 6.5-dev nightly `2026-05-12-a` might be
blocked on `swift-array-primitives` by the known DeinitDevirtualizer
SIL assertion (catalog Master Fix-Status Table). Tested against the
standalone SwiftPM reproducer at
`swift-foundations/swift-executors/Experiments/sigsegv-repro/`:

| Toolchain | Bundle ID | Build | Run |
|-----------|-----------|-------|-----|
| Apple Swift 6.3.2 (default) | `swift-6.3.2-RELEASE` | OK | **CRASH** (exit 139) |
| Swift 6.5-dev `2026-05-12-a` | `org.swift.64202605121a` | OK (debug + release) | **PASS** (exit 0) |
| Swift 6.5-dev `2026-05-07-a` | `org.swift.64202605071a` | OK | **PASS** (exit 0) |
| Swift 6.5-dev `2026-03-16-a` | `org.swift.64202603161a` | OK | **PASS** (exit 0) |

The DeinitDevirtualizer blocker DOES affect a full
`swift-executors swift test` run on 6.5-dev (the `swift-array-primitives`
transitive dep hits the SIL assertion), but DOES NOT block the
standalone reproducer build (the reproducer's three direct deps
`swift-tagged-primitives` / `swift-ordinal-primitives` /
`swift-cardinal-primitives` do not transit through `swift-array-primitives`).

The standalone reproducer passes on every 6.5-dev nightly we sampled.
The bug is fixed in the 6.4-dev → 6.5-dev nightly stream by
`2026-03-16-a` (the earliest 6.4-dev nightly available locally past the
6.3.2 ship). The exact commit window is somewhere in the
~5-month gap between 6.3.2's release and `2026-03-16-a`; pinpointing
it is deferred to upstream filing.

### [`ISSUE-002`] Bare-`swiftc` reduction — five-shape attempt; v1 untested

Five reduction shapes were attempted (full source in `/tmp/sigsegv-bare/`,
not committed):

| Shape | Description | Result on 6.3.2 |
|-------|-------------|-----------------|
| **v1** single-file with full Tagged | `@frozen`, `package(set)`, `@_lifetime`, `~Escapable` storage, all conformances | **NOT TESTED** — compile-errored at the unflagged `swiftc` invocation; the errors (`-package-name` / `-enable-experimental-feature Lifetimes` / `~Escapable`-storage ergonomics) are resolvable with the required flag scaffolding, but the retry was not performed |
| v2 single-file simplified Tagged | Without `package(set)`/`@_lifetime`/`~Escapable`; inline `AtomicRepresentable` conformance; `Atomic<Tagged>.load + compareExchange` | **PASS** (no crash) |
| v3 two-module split (Tagged in module A; consumer in B) | Inline conformance in module A (no SLI submodule) | **PASS** |
| v4 three-module split (Tagged / `@retroactive AtomicRepresentable` conformance / consumer) | Conformance in separate module, imported by consumer | **PASS** |
| v5 four-module split with generic Atomic extension | Tagged / Conformance / Atomic extension `bumpZero` / consumer | **PASS** |

Per [`ISSUE-026`] coverage-scope discipline, the truthful conclusion
from this experiment is:

> v2–v5 (simplified-Tagged single-file + 2/3/4-module splits) all PASS
> on 6.3.2 — none of the four *simplified* bare-`swiftc` shapes
> reproduces. Combined with Arc 3's evidence (single-file edits to
> Tagged.swift don't fix the crash) and Arc 1's variable-isolation
> evidence (a local wrapper struct mirroring Tagged's shape doesn't
> reproduce), the *conditional* conclusion is consistent: the
> production `Tagged_Primitives.Tagged` symbol with its production
> module structure appears to be load-bearing.
>
> The v1 hypothesis (full-attribute single-file with all required
> flag scaffolding) is **UNTESTED**. It may reproduce in isolation; it
> may not. The five-shape attempt does NOT empirically close that
> question. Pursuing v1 is deferred — per [`ISSUE-008`] resolution
> path ("Fixed on dev toolchain, not in Xcode → apply workaround,
> document, wait for release"), further reduction effort is not
> load-bearing for the resolution decision.

The reproducer documented here therefore preserves
`import Tagged_Primitives` (with `Ordinal_Primitives` /
`Cardinal_Primitives` for the `.advance(within:)` extension and the
`Cardinal` Underlying), per [`ISSUE-002`]'s "If the issue requires
SwiftPM" branch — *accommodating* the SwiftPM dependency, not
*proving* SwiftPM is required.

This is unusual for the per-issue convention but accommodated.
`swift-issue-spm-planning-build-stall/` is the existing precedent for a
SwiftPM-only Issues entry (different bug class — planner-stage stall
on multi-package workspace topology — and an empirically closed
"no single-`swift` reproducer" claim for that planner-stage bug).

### [`ISSUE-007`] Duplicate search

`gh search issues` against `swiftlang/swift`:

| Issue | State | Domain | Same root cause? |
|-------|-------|--------|------------------|
| [`#74303`](https://github.com/swiftlang/swift/issues/74303) — "Runtime Crash at __swift_instantiateConcreteTypeFromMangledName" | OPEN | DiscordBM `IntBitField<DiscordApplication.Flag>?` Codable+Optional bitfield | Same family (`swift_getTypeByMangledName` TypeLookupError), different domain |
| [`#69615`](https://github.com/swiftlang/swift/issues/69615) — "TypeLookupError for getTypeByMangledNameInContext" | OPEN | Kubrick `@JobBuilder buildBlock` opaque-return-type metadata | Same family, different domain |
| #74333 — closed dupe of #74303 | CLOSED | — | — |

No exact duplicate for the Tagged + Atomic + `~Copyable`
conditional-conformance shape. The two open issues confirm that the
`swift_getTypeByMangledName → TypeLookupError("unknown error")` failure
mode is a broader runtime defect class that surfaces in distinct
domains; our entry would be a new sibling instance.

### [`ISSUE-008`] Resolution path

The skill's resolution path for "Fixed on dev toolchain, not in Xcode"
is:

> Apply workaround, document, wait for release.

The orchestrator's standing correctness preference (memory entry
`feedback_correctness_and_evergreen.md`) rules out the typed-wrapper
workaround that Arc 2 explored. The applied resolution for this arc is
therefore:

1. Stage this Issues entry (this directory) as the canonical
   public-facing reproducer + record.
2. Update catalog §A9 with the dev-toolchain status (fixed on 6.5-dev).
3. Append `§Findings (2026-05-23 Arc 4)` to
   `HANDOFF-tagged-noncopyable-atomic-metadata-crash.md`.
4. Stage a sibling-comment data-point draft for posting on
   [`swiftlang/swift#74303`](https://github.com/swiftlang/swift/issues/74303),
   the existing open issue covering the same
   `__swift_instantiateConcreteTypeFromMangledName`-null-return
   failure family in a different domain (DiscordBM
   `IntBitField<Flag>?` Codable+Optional). Draft at
   [`SIBLING-COMMENT-DRAFT.md`](SIBLING-COMMENT-DRAFT.md); posting is
   pending orchestrator authorization per [`ISSUE-008`]. This posture
   replaces the earlier "backport-request" framing — given the bug is
   already fixed on 6.5-dev and the failure mode is a tracked family
   with existing open instances, a sibling-instance comment is the
   appropriate ask rather than a new issue or a 6.3.x-backport request.
5. Wait for the Swift 6.5 release. The three handoff-flagged packages
   (swift-executors, swift-threads, swift-io) will pass on 6.5+ with no
   source change.

---

## Files added by this arc

- `swift-institute/Issues/swift-issue-tagged-noncopyable-atomic-metadata-crash/` — this directory
  - `README.md`
  - `INVESTIGATION-ARC.md` (this file)
  - `SIBLING-COMMENT-DRAFT.md` (data-point comment for swiftlang/swift#74303)
  - `Sources/Reproducer/main.swift`
  - `Tests/Reproducer.swift`
- `swift-institute/Issues/Package.swift` — two new targets +
  three external dependencies (per the brief's accommodation of the
  SwiftPM-only-reproducer case)
- `HANDOFF-tagged-noncopyable-atomic-metadata-crash.md` — appended
  `§Findings (2026-05-23 Arc 4)`
- `swift-institute/Research/swift-compiler-bug-catalog.md` — §A9
  updated with dev-toolchain-fix status + Issues-directory reference

No production source files were modified. The four revert commits
(`e46b3b7` / `106d914` / `44ab1f8` / `b77a4f03`) stay landed. The
parallel `swift-issue-parameterized-typealias-opaque-return-ice/`
untracked directory was not touched.

---

## Ecosystem blast radius (orchestrator 2026-05-23)

A `Sources/`-only ecosystem-wide grep across the 16 workspace orgs
identified the following call sites of the failing shape:

### Confirmed crash sites — 4 across 3 packages

| # | Package | File:line | Shape |
|---|---------|-----------|-------|
| 1 | `swift-foundations/swift-executors` | `Sources/Executors/Kernel.Thread.Executor.Sharded.swift:46,57` | `Atomic<Index<Kernel.Thread>>` |
| 2 | `swift-foundations/swift-executors` | `Sources/Executors/Kernel.Thread.Executor.Stealing.swift:57` | `Atomic<Index<Kernel.Thread>>` |
| 3 | `swift-foundations/swift-kernel` | `Sources/Kernel Event/Kernel.Event.Driver.swift:103` | `Dictionary_Primitives.Dictionary<Kernel.Event.ID, Registration>` |
| 4 | `swift-foundations/swift-io` | `Sources/IO Completions/Completion.Actor.swift:86` | `Dictionary<Kernel.Completion.Token, Completion.Entry>` |

### Possibly affected, NOT yet tested

| # | Package | File:line | Shape |
|---|---------|-----------|-------|
| 5 | `swift-primitives/swift-tree-primitives` | `Sources/Tree Keyed Primitives/Tree.Keyed.swift:93,106` | `Dictionary_Primitives.Dictionary<Key, Index<Node>>.Ordered` (Index on VALUE side, not key) |

### Discrimination signal — what does NOT trigger

`swift-linter` runs clean on `swift-carrier-primitives` with a clean
`rm -rf .build`, exit 0. swift-linter uses `[Lint.Rule.ID: Lint.Rule]`
and `[Lint.Rule.ID: Lint.Rule.Configuration]` where
`Lint.Rule.ID = Tagged<Lint.Rule, Swift.String>`. So **stdlib Dictionary
keyed by Tagged with a Copyable Value does NOT trigger the bug**.

The 15-site ecosystem-wide `Atomic<…>` audit shows that every other
`Atomic<…>` usage in the workspace wraps a primitive
(Int / UInt64 / Bool / UInt8) and does NOT trigger. The 3 executor-cursor
sites (Sharded + Stealing) are the canonical Atomic-axis crash shape.

### Three-axis bisection matrix (open)

The orchestrator-mapped axes for narrowing the trigger further:

| Axis | Question | Tested? | Current evidence |
|------|----------|---------|------------------|
| A | Does plain `Atomic<Tagged<Copyable_X, Copyable_U>>` crash by itself, or is `Tag: ~Copyable` / `Underlying: ~Copyable` load-bearing on the conformance side? | PARTIAL | `Atomic<Tagged<Tag, Ordinal>>.load` PASSES; only the `.advance(within:)` generic extension method crashes (catalog §A9 var-isolation rows 4–5). Whether the `Tag: ~Copyable` clause on the conformance is load-bearing was refuted by Arc 1's empirical Shape A1 test. The OPEN question is whether a generic extension method that doesn't require the Ordinal.Protocol constraint chain (i.e. a simpler full-metadata-instantiating method on `Atomic<Tagged<X, UInt>>`) still triggers. Bare-`swiftc` four-module variant with simpler generic extension `bumpZero` (Axis A bare-substrate) PASSES — but that's on a local-copy Tagged, not `Tagged_Primitives.Tagged`. |
| B | Container choice: does stdlib `Swift.Dictionary<TaggedKey, ~Copyable Value>` crash, or only `Dictionary_Primitives.Dictionary<TaggedKey, ~Copyable Value>`? | OPEN | Sites 3 (kernel) and 4 (io) both crash; site 3 uses `Dictionary_Primitives.Dictionary`, site 4 uses `Swift.Dictionary`. Both crash, both have `~Copyable` Value. So stdlib Dictionary alone is NOT a discriminator — Value-side suppression appears load-bearing. |
| C | Value-side suppression: does `Dictionary<TaggedKey, Copyable_Value>` crash, or is `~Copyable Value` required? | PARTIAL | swift-linter's `[Lint.Rule.ID: Lint.Rule]` with Copyable Value PASSES (stdlib Dictionary). Site 3 (institute Dictionary, ~Copyable Value) CRASHES. Site 4 (stdlib Dictionary, ~Copyable Value) CRASHES. Untested: institute Dictionary + Copyable Value. The collapsing-cells signal: `~Copyable` Value appears to be the load-bearing trigger for the Dictionary family, independent of stdlib-vs-institute container. |

The collapsing of Axis B + Axis C signal suggests the unified bug shape
is:

> Any generic container that needs the full type metadata of
> `Tagged_Primitives.Tagged<…>` materialized for dispatch — AND whose
> dispatch involves a `~Copyable` constraint somewhere in the
> instantiation chain — triggers the demangling-time
> `TypeLookupError("unknown error")` on 6.3.x.

The Atomic case adds `~Copyable Self` (Atomic is itself
`~Copyable`); the Dictionary case adds `~Copyable Value`. Both
container shapes share: Tagged-on-the-key / Tagged-on-the-Self side
of the type + a `~Copyable` somewhere in the type's full mangled name.
The runtime's demangler appears to fail specifically on this
combination's inline-name resolution path for cross-module conformance
references, on 6.3.x only.

Pinpointing further requires upstream-side bisection of the
6.3.2 → 6.5-dev nightly stream — out of scope for this arc per
[`ISSUE-022`].
