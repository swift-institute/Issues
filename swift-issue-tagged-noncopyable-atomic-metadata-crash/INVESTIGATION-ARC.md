# Investigation Arc: Tagged + Atomic + `~Copyable` Runtime Metadata SIGSEGV

This document carries forward the four-arc convergence record. The
canonical bug-catalog entry for this defect is
`swift-institute/Research/swift-compiler-bug-catalog.md` §A9 (commit
`ba4b911`). The workspace-side investigation handoffs that produced this
record are an internal working document (Arcs 1–3) and
an internal working document (Arc 4).

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
an internal feedback note, structural correctness +
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
| Swift 6.4-dev `2026-05-07-a` | `org.swift.64202605071a` | OK | **PASS** (exit 0) |
| Swift 6.4-dev `2026-03-16-a` | `org.swift.64202603161a` | OK | **PASS** (exit 0) |

The DeinitDevirtualizer blocker DOES affect a full
`swift-executors swift test` run on 6.5-dev (the `swift-array-primitives`
transitive dep hits the SIL assertion), but DOES NOT block the
standalone reproducer build (the reproducer's three direct deps
`swift-tagged-primitives` / `swift-ordinal-primitives` /
`swift-cardinal-primitives` do not transit through `swift-array-primitives`).

The standalone reproducer passes on every 6.4-dev / 6.5-dev nightly we sampled.
The bug is fixed in the 6.4-dev → 6.5-dev nightly stream by
`2026-03-16-a` (the earliest 6.4-dev nightly available locally past the
6.3.2 ship). The exact commit window is somewhere in the
~5-month gap between 6.3.2's release and `2026-03-16-a`; pinpointing
it is deferred to upstream filing.

### [`ISSUE-002`] Bare-`swiftc` reduction — five-shape attempt; v1 retried and PASS

Five reduction shapes were attempted (full source in `/tmp/sigsegv-bare/`
for v2–v5 and `/tmp/sigsegv-v1/` for v1, not committed):

| Shape | Description | Result on 6.3.2 |
|-------|-------------|-----------------|
| **v1** single-file with full Tagged | `@frozen`, `package(set)`, `@_lifetime`, `~Escapable` storage, all conformances, `modify` extension, inline `AtomicRepresentable` conformance | **PASS** — Trigger A (`Atomic<Tagged<SimpleTag, Int>>.load(ordering: .relaxed)`) AND Trigger B (`Atomic<Tagged<SimpleTag, UInt>>.bumpZero(within:)` with same-type-constraint-chain extension matching production `.advance(within:)`'s where-clause shape) both compile + run + exit 0 under `swiftc -O -package-name v1pkg -enable-experimental-feature Lifetimes -enable-experimental-feature SuppressedAssociatedTypes`. Files at `/tmp/sigsegv-v1/v1_trigger_a.swift` (123 lines) and `/tmp/sigsegv-v1/v1_trigger_b.swift` (164 lines), not committed |
| v2 single-file simplified Tagged | Without `package(set)`/`@_lifetime`/`~Escapable`; inline `AtomicRepresentable` conformance; `Atomic<Tagged>.load + compareExchange` | **PASS** (no crash) |
| v3 two-module split (Tagged in module A; consumer in B) | Inline conformance in module A (no SLI submodule) | **PASS** |
| v4 three-module split (Tagged / `@retroactive AtomicRepresentable` conformance / consumer) | Conformance in separate module, imported by consumer | **PASS** |
| v5 four-module split with generic Atomic extension | Tagged / Conformance / Atomic extension `bumpZero` / consumer | **PASS** |

Per [`ISSUE-026`] coverage-scope discipline, the truthful conclusion
from this experiment (post v1 retry) is:

> v1 (full-attribute production-verbatim single-file with required
> four-flag scaffolding) AND v2–v5 (simplified-Tagged single-file +
> 2/3/4-module splits) **all PASS** on 6.3.2 — none of the five
> bare-`swiftc` shapes reproduces. Combined with Arc 3's
> nine-candidate `Tagged.swift` single-file bisection (also failed to
> fix the crash) and Arc 1's variable-isolation evidence (a local
> wrapper struct mirroring Tagged's shape doesn't reproduce), the
> production `Tagged_Primitives.Tagged` symbol with its production
> module structure is **strongly supported** as the load-bearing
> trigger — not just consistent with prior evidence but empirically
> tested against the strongest single-file approximation we could fit.
>
> **Remaining caveat**: v1's Trigger B drops the specific protocol
> identities used by production `.advance(within:)` —
> `Ordinal.\`Protocol\``, `Carrier.\`Protocol\`<Cardinal>`,
> `Cardinal` — because inlining them would exceed a reasonable
> single-file budget (~200 lines). Trigger B captures the *shape* of
> the same-type-constraint chain
> (`Value.AtomicRepresentation == UInt.AtomicRepresentation`
> + `C.AtomicRepresentation == UInt.AtomicRepresentation`) that
> production `.advance(within:)` uses, but not the protocol
> *identities*. If the bug is gated by the specific
> Ordinal/Carrier/Cardinal protocol identities rather than the
> constraint shape, that cell remains untested. A Trigger C with full
> protocol-identity scaffolding was orchestrator-decided 2026-05-23
> to be diminishing returns (per [`ISSUE-008`] resolution path
> "Fixed on dev toolchain, not in Xcode → wait for release", further
> reduction is not load-bearing for the resolution decision).

The reproducer documented here therefore preserves
`import Tagged_Primitives` (with `Ordinal_Primitives` /
`Cardinal_Primitives` for the `.advance(within:)` extension and the
`Cardinal` Underlying), per [`ISSUE-002`]'s "If the issue requires
SwiftPM" branch — *accommodating* the SwiftPM dependency, with the
five-shape + nine-candidate evidence as strong support for that
accommodation.

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
an internal feedback note) rules out the typed-wrapper
workaround that Arc 2 explored. The applied resolution for this arc is
therefore:

1. Stage this Issues entry (this directory) as the canonical
   public-facing reproducer + record.
2. Update catalog §A9 with the dev-toolchain status (fixed on 6.5-dev).
3. Append `§Findings (2026-05-23 Arc 4)` to
   an internal working document.
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
- an internal working document — appended
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

### `Set.Ordered` axis extension (2026-06-01)

A new site of the same family surfaced while greening
`swift-graph-primitives` (queue dissolve-Core cascade): `swift test`
SIGSEGVs although the package builds green. The element type is
`Graph.Node<Tag> = Index<Tag> = Tagged<Tag, Ordinal>` (two typealias
hops), so the literal `Set<Tagged…>`/`Set<Index…>` grep used on
2026-05-23 did not catch it — the new search angle is *"`Set.Ordered`
whose element resolves to `Tagged` through any typealias chain."*

Signature-confirmed with a 3-package, zero-graph-code reproducer
(`swift-set-ordered-primitives` + `swift-set-primitives` +
`swift-index-primitives`): `Set<Index<SimpleTag>>.Ordered().insert(.zero)`
on Apple Swift 6.3.2 prints `failed type lookup … unknown error`
(`SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1`) and exits 139 — the exact §A9
`swift_getTypeByMangledName` null-metadata signature. The forcing path is
`Hash.Table` insert needing the element's value-witness table, i.e. the
same path as confirmed Dictionary sites #3/#4, in a different container.

| # | Package | Site | Status on 6.3.2 |
|---|---------|------|-----------------|
| 6 | `swift-primitives/swift-graph-primitives` | `Set<Graph.Node<Tag>>.Ordered` in `Analyze.Reachable` / `Analyze.Dead` / `Reverse.Reachable` constructors (+ `Transform.Subgraph` consumer) | **CRASH** (confirmed) |
| 7 | `swift-primitives/swift-dictionary-ordered-primitives`, `swift-dictionary-primitives` | `_keys: Set<Key>.Ordered` (generic carrier) | **CRASH** iff `Key` is `Index`/`Tagged` (latent) |
| 8 | `swift-primitives/swift-index-primitives` | plain `Set<Index<Int>>` (non-`.Ordered`; tests) | LIKELY CRASH — same VWT path, untested 2026-06-01 |

**Dev-toolchain (PASS-on-dev)**: no 6.4-dev+ snapshot is currently
installed; this site inherits the family fix (Arc 4 toolchain matrix +
Arc 7 controlled compiler/runtime swap → incomplete `SuppressedAssociatedTypes`
codegen, fix complete by 6.4-dev). A per-container re-confirm was deemed
low marginal value (orchestrator decision 2026-06-01); the accurate gate
is `compiler(<6.4)`.

**Consumer mitigation**: graph's four uniformly-affected suites
(`Transform.Subgraph`, `Analyze.Dead`, `Reachability`, `Reverse.Reachable`)
were guarded with a suite-level `.disabled(if: Toolchain.hasTaggedMetadataSIGSEGV, …)`
trait. `.disabled(if:)` rather than `withKnownIssue` because a SIGSEGV
kills the runner before swift-testing can register a known issue (see the
README §"Swift Testing harness" note) — only skipping the body yields a
clean 6.3.2 run; the guard auto-recovers on 6.4+.

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

---

## Arc 5 (2026-05-23) — Commit bisection

Identified fix at HIGH confidence: [PR #87066](https://github.com/swiftlang/swift/pull/87066) / commit [`bc44d42f11`](https://github.com/swiftlang/swift/commit/bc44d42f11830ea37a3b882e332ef480c1b4324e) ("SuppressedAssociatedTypesWithDefaults: swiftinterface and mangling support", merged 2026-02-10 by @kavon). The 14-line addition to `lib/Demangling/Demangler.cpp` adds cases `'j'` (Inverse + Assoc) and `'J'` (Inverse + CompoundAssoc) to `Demangler::demangleGenericRequirement()`. Verified absent from `release/6.3` / `release/6.3.1`; present on `release/6.4.x` and `main`. PR explicitly added test coverage at `test/Casting/suppressed-associated-types.swift`. Confidence vectors: source-mechanism match + PR-body runtime-breakage acknowledgment + cherry-pick absence on `release/6.3`.

## Arc 6 (2026-05-23) — Drafts + audit + posting closeout

Three artifacts staged + audited + posted:

- **Backport request issue** filed at [swiftlang/swift#89389](https://github.com/swiftlang/swift/issues/89389) — narrowed to `release/6.3` only (`release/6.4.x` already carries `bc44d42f11`).
- **Sibling-instance comment** posted on [swiftlang/swift#74303](https://github.com/swiftlang/swift/issues/74303#issuecomment-4524878679) — cites identified fix + cross-platform CI matrix + links the backport-request issue.
- **§A9 catalog correction** landed at swift-institute/Research commit `aa94a98` — additive snapshot version-label correction (`2026-03-16-a` and `2026-05-07-a` are 6.4-dev, not 6.5-dev as the prior Arc 4 update labeled).

### Pre-post audit (Arc 6 fresh-perspective review)

A fresh-chat audit verified every empirical claim against verifiable sources (`gh api`, file:line reads, CI run inspection) and minimized public-text length to ≤200 words sibling comment + ≤350 words backport request (prose-only count). Key corrections caught and folded in:

- **C-19** (snapshot version labels): catalog §A9 mislabeled two snapshots as 6.5-dev; empirical `swift --version` shows they are 6.4-dev. Reviewed drafts use neutral "main-branch nightly" framing; catalog §A9 amended additively.
- **C-22** (#74333 disposition): not a duplicate of #74303 as prior drafts claimed; state is `CLOSED` with `stateReason: COMPLETED`. Removed.
- **C-30** (statement count): `main.swift` has 9 statements, not "~13".
- **C-35/36/37** (platform claim): "platform-independent — likely affects every host" empirically refuted. CI run [26326702012](https://github.com/swift-institute/Issues/actions/runs/26326702012) shows: macOS Apple 6.3.2 CRASH; swift.org Linux 6.3.2 NO CRASH (same `swift-6.3.2-RELEASE` source tag); Windows ambiguous. Bug is Apple-toolchain-specific within the release/6.3 lineage.
- **C-38** (CI confound): macOS leg runs `-c debug` and Linux 6.3 leg runs `-c release`; CI doesn't fully isolate platform vs build mode. Reviewed drafts disclose this and note local testing on Apple Xcode 6.3.2 reports CRASH under both `-Onone` and `-O`.

Audit details + full 40-row claim inventory at [`AUDIT-REPORT.md`](AUDIT-REPORT.md). Reviewed drafts at [`REVIEWED-BACKPORT-REQUEST.md`](REVIEWED-BACKPORT-REQUEST.md) and [`REVIEWED-SIBLING-COMMENT.md`](REVIEWED-SIBLING-COMMENT.md). Historical Arc 4 / Arc 6 drafts retained at [`BACKPORT-REQUEST-DRAFT.md`](BACKPORT-REQUEST-DRAFT.md) and [`SIBLING-COMMENT-DRAFT.md`](SIBLING-COMMENT-DRAFT.md).

## Arc 7 (2026-05-28) — Arc 5 diagnosis REFUTED; root cause is codegen, not the demangler

@kavon pushed back on #89389 ([comment](https://github.com/swiftlang/swift/issues/89389#issuecomment-4547334121)): `release/6.3` does not have a complete `SuppressedAssociatedTypesWithDefaults` implementation, so why backport the feature? Re-verification proved **Arc 5 was wrong**.

Arc 5 "bisection" was a code-search heuristic, never an experiment. A controlled compiler/runtime swap of the reproducer refutes the demangler diagnosis:

| Binary built by | Runtime (`libswiftCore`) | Result |
|-----------------|--------------------------|--------|
| 6.3.2 | 6.3.2 (OS) | CRASH (139) |
| 6.3.2 | 6.4-dev nightly `2026-03-16-a` (fixed demangler loaded, confirmed) | **CRASH (139)**, same deref |
| 6.4-dev nightly `2026-03-16-a` | 6.3.2 (OS) | **PASS (`result = 0`)** |

The fix travels with the binary, not the runtime → **emission (compiler), not the demangler**. `bc44d42f11` is demangler-only (+14/−0) and would NOT fix `release/6.3`-compiled code. The emitted symbolic mangled name for `Atomic<Tagged<…>>` differs structurally between 6.3.2 and 6.4-dev (spurious `_` after the 46-char SLI identifier; `HCHCg` vs `HC_HCg`) — malformed emission.

This is the incomplete-on-6.3 `SuppressedAssociatedTypes` feature (production enables the flag in swift-tagged-primitives + swift-ordinal-primitives; the crashing `.advance(within:)` is constrained on `Ordinal.Domain: ~Copyable`). Exact fixing commit not bisected. kavon's framing was correct.

**Disposition**: #89389 reply posted conceding + withdrawing the request ([comment](https://github.com/swiftlang/swift/issues/89389#issuecomment-4563419364)); #74303 note corrected; this doc, README, BACKPORT-REQUEST-DRAFT, and catalog §A9 updated. Earlier Arc 1–6 demangler framing throughout this file is superseded by this arc — retained as historical record. Consumer resolution: require Swift 6.4+ for these paths.
