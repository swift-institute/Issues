# Swift Issue: Tagged + Atomic + `~Copyable` cross-module conditional-conformance runtime metadata SIGSEGV

> **CORRECTION (2026-05-28).** This document's diagnosis below (and the original
> filings) blamed the **demangler** — a missing `'j'`/`'J'` inverse-assoc case
> (`bc44d42f11`) — and asked for a `release/6.3` cherry-pick. **That was wrong.**
> A controlled compiler/runtime swap shows the fault is **codegen (compiler
> emission), not the demangler**: a 6.3.2-built binary crashes even on a fixed
> 6.4-dev runtime, while a 6.4-dev-built binary runs clean on the 6.3.2 runtime.
> This is the `SuppressedAssociatedTypes` experimental feature, whose codegen is
> incomplete on 6.3 and complete by 6.4-dev (the crashing `.advance(within:)` is
> constrained on `Ordinal.Domain: ~Copyable`). `bc44d42f11` would NOT fix
> 6.3-compiled code. Backport-request #89389 withdrawn; #74303 note corrected.
> See INVESTIGATION-ARC.md Arc 7 and catalog §A9 Correction (2026-05-28).
> The demangler framing throughout the rest of this file is superseded.

**Status**: RESOLVED on Swift 6.4-dev / 6.5-dev nightly (verified 2026-05-23 against
snapshots `2026-03-16-a` (6.4-dev), `2026-05-07-a` (6.4-dev), `2026-05-12-a` (6.5-dev));
STILL FIRES on Apple Swift 6.3.x (`swiftlang-6.3.2.1.108`, current Xcode 26.4.1).
Root cause: **compiler codegen** for the incomplete-on-6.3 `SuppressedAssociatedTypes`
feature — not the runtime demangler (see Correction above).

**Upstream filing posture**: sibling-comment on
[`swiftlang/swift#74303`](https://github.com/swiftlang/swift/issues/74303)
— a data-point comment on the existing open `__swift_instantiateConcreteTypeFromMangledName`-null-return issue,
NOT a new issue and NOT a backport request. Posting
requires orchestrator authorization per [`ISSUE-008`]. See
"Upstream status and process-document consolidation" below for the
audited draft content and current upstream link states.

**Classification**: Runtime miscompile / crash (per
[`ISSUE-010`]). The compiler accepts the source and emits a binary; at
runtime the type-metadata cache stub
`__swift_instantiateConcreteTypeFromMangledNameV2` returns null when
asked to instantiate
`Synchronization.Atomic<Tagged_Primitives.Tagged<Tag, Ordinal_Primitive.Ordinal>>`,
and the caller's generic-dispatch dereferences `[null + 0x10]` →
`EXC_BAD_ACCESS (code=1, address=0x10)` → SIGSEGV.

**Toolchain matrix**:

| Toolchain | Identifier | Result |
|-----------|------------|--------|
| Apple Swift 6.3.2 RELEASE (Xcode 26.4.1, default) | `swiftlang-6.3.2.1.108` | **CRASH** (exit 139) |
| Apple Swift 6.3.1 RELEASE | `swift-6.3.1-RELEASE` | **CRASH** (per prior arc) |
| Swift 6.4-dev nightly 2026-03-16-a | `org.swift.64202603161a` | **PASS** (exit 0) |
| Swift 6.4-dev nightly 2026-05-07-a | `org.swift.64202605071a` | **PASS** (exit 0) |
| Swift 6.5-dev nightly 2026-05-12-a | `org.swift.64202605121a` | **PASS** (exit 0; debug + release) |

The exact 6.3.x → 6.4-dev → 6.5-dev fix landing window is narrower
than the snapshot bisection captured: by `2026-03-16-a` (the earliest
nightly we sampled past the 6.3.2 cut), the bug no longer fires. The
6.4-dev nightly stream between 6.3.2's ship date and `2026-03-16-a`
contains the fix; pinpointing the exact commit is deferred to upstream
filing (fix identification: `bc44d42f11` in PR #87066 — see the
consolidation section below).

---

## Crash signature

```
EXC_BAD_ACCESS (code=1, address=0x10) at
Atomic<Tagged_Primitives.Tagged<Tag, Ordinal_Primitive.Ordinal>>.advance(within:)+92

Frame: __swift_instantiateConcreteTypeFromMangledNameV2 (compiler-generated)
  → swift_getTypeByMangledNameInContext2 (thin PAC wrapper)
  → swift_getTypeByMangledNameInContextImpl (sets up substitution closures)
  → swift_getTypeByMangledName  ← returns TypeLookupError("unknown error")
```

When the runtime is observed via `SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1` the
preceding stderr line is:

```
failed type lookup for <symbolic-mangled-name>: unknown error
```

where the symbolic name decodes to (per the prior arc's lldb
breakpoint walk):

```
Synchronization.Atomic
  Tagged_Primitives.Tagged
    SimpleTag (or POSIX.Kernel.Thread, etc. — Tag identity is irrelevant)
    Ordinal_Primitive.Ordinal
  [extension-context: 46-char inline identifier]
    Tagged_Primitives_Standard_Library_Integration
  [trailer with back-references + Sendable witness marker]
```

The 46-character inline-encoded identifier
`Tagged_Primitives_Standard_Library_Integration` is the submodule that
defines the conditional conformance
`extension Tagged: AtomicRepresentable where Underlying: AtomicRepresentable, Tag: ~Copyable`.
The runtime's demangling-time conformance lookup for this inline-name
fragment returns the default-constructed `TypeLookupError("unknown error")`
on 6.3.x, before any of the high-level
`swift_lookUpProtocolConformance` / `swift_getAssociatedTypeWitness` /
`swift_getCanonicalSpecializedMetadata` entry points dispatch. See
[`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) §"Runtime descriptor lookup
result" for the lldb walk that pinpointed the failing demangler path.

---

## Trigger characterization

| Element | Required for crash? | Evidence |
|---------|---------------------|----------|
| `Atomic<Value>` with `Value: AtomicRepresentable` | YES — `Atomic<UInt>` PASSES with the same `.advance` extension | Catalog §A9 var-isolation row 1 |
| `Tagged<Tag, Underlying>` (vs. concrete `Underlying`) | YES — `Atomic<Ordinal>.advance(within: Cardinal)` PASSES | Catalog §A9 row 2 |
| Generic extension method on `Atomic` requiring full type metadata | YES — `Atomic<Tagged<…>>.load` PASSES; only `.advance` crashes | Catalog §A9 rows 4–5 |
| Cross-module `Tagged: AtomicRepresentable` conformance | YES — local `Tagged` look-alike in the same module as the consumer does NOT reproduce | Prior arc + this arc's bare-`swiftc` reduction |
| `Tagged_Primitives.Tagged` specifically (not a local equivalent) | YES — a local wrapper mirroring Tagged's exact declaration shape does NOT reproduce | Prior arc 2026-05-22 + this arc's 4-module bare-`swiftc` attempt |
| `Tag: ~Copyable` clause on the conformance | NO — dropping it does not fix the crash | Prior arc 2026-05-22 (Shape A1 refuted) |
| Specific Tag identity | NO — `enum SimpleTag: Sendable {}` reproduces identically to `POSIX.Kernel.Thread` | Catalog §A9 |
| `@frozen` / `package(set)` / `~Escapable` on `Tagged` storage | NO — the 9-candidate 2026-05-23 single-file bisection of `Tagged.swift` failed to fix the bug | Prior arc Arc 3 §Findings |

The bug is specific to the production `Tagged_Primitives.Tagged` symbol
materialized inside a generic stdlib container whose runtime dispatch
needs the full `Atomic<Tagged<…>>` metadata. Neither a local-copy nor a
single-file change to `Tagged.swift` reproduces or fixes it.

---

## Additional sites (same family)

The defect is container-agnostic (axis-B): any generic container that
forces `Tagged_Primitives.Tagged`'s full type metadata at runtime hits
the same `swift_getTypeByMangledName` → `TypeLookupError("unknown error")`
null-metadata path.

| Site | Forcing path | Discovered | Confirmation |
|------|--------------|------------|--------------|
| `Atomic<Tagged<…>>.advance(within:)` | generic `@inlinable` extension dispatch | 2026-05-22 | original |
| `Dictionary<Tagged<…>, ~Copyable>.set/.remove` | hash-table insert needs Tagged VWT | 2026-05-22 | original |
| **`Set<Tagged/Index>.Ordered.insert(_:)`** | **`Hash.Table` insert needs Tagged VWT** | **2026-06-01** | **3-package reproducer, signature-confirmed** |

**`Set.Ordered` site (2026-06-01).** Found while greening
`swift-graph-primitives` during the queue dissolve-Core cascade: graph
builds green (debug + release) but `swift test` SIGSEGVs.
`Index_Primitives.Index<E> = Tagged<E, Ordinal>` and
`Graph.Node<Tag> = Index<Tag>`, so graph's
`Set<Graph.Node<Tag>>.Ordered.insert` is `Set<Tagged<…>>.Ordered.insert`
via two typealias hops. A minimal 3-package reproducer with **zero graph
code** (`swift-set-ordered-primitives` + `swift-set-primitives` +
`swift-index-primitives`) crashes identically:

```swift
import Set_Ordered_Primitives; import Set_Primitives; import Index_Primitives
enum SimpleTag {}
var set = Set<Index<SimpleTag>>.Ordered()
set.insert(Index<SimpleTag>.zero)   // ← SIGSEGV
```

```
$ SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1 .build/debug/repro
failed type lookup for �$: unknown error
[exit 139]
```

Blast radius (2026-06-01): graph `Set<Graph.Node>.Ordered` in
`Analyze.Reachable` / `Analyze.Dead` / `Reverse.Reachable` (+ `Transform.Subgraph`
consumer); latent generic carriers `Dictionary.Ordered`/`Dictionary`
(`_keys: Set<Key>.Ordered`, crash iff `Key` is `Index`/`Tagged`); candidate
plain `Set<Index>` (same VWT path, untested). Graph's four affected test
suites were guarded with a suite-level `.disabled(if:)` trait gated on
`compiler(<6.4)` (not `withKnownIssue` — see the §"Swift Testing harness"
note below: a SIGSEGV kills the runner before a known issue can register,
so only skipping the body yields a clean 6.3.2 run).

---

## Reproducer

This reproducer requires **SwiftPM with three external dependencies**.
Bare-`swiftc` reduction was attempted across five shapes (see
[`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) §`[ISSUE-002]`):

- **v1 (full-attribute single-file)** — Tagged declaration mirroring
  production verbatim (`@_lifetime(copy underlying)`, `package(set)`,
  struct-level `~Escapable`, the full conditional Copyable / Escapable
  / Sendable / BitwiseCopyable / Equatable / Hashable / Comparable
  conformance chain, the `modify` extension, and the
  `AtomicRepresentable` conformance from the SLI submodule). Built
  with the required four-flag scaffolding
  (`swiftc -O -package-name v1pkg
  -enable-experimental-feature Lifetimes
  -enable-experimental-feature SuppressedAssociatedTypes`). Tested
  with two triggers: (A) `Atomic<Tagged<SimpleTag, Int>>.load(ordering: .relaxed)`,
  (B) a generic-extension `bumpZero<C>(within:)` on `Atomic` whose
  where-clause chain (`Value.AtomicRepresentation == UInt.AtomicRepresentation`
  + `C.AtomicRepresentation == UInt.AtomicRepresentation`) mirrors
  production `.advance(within:)`'s metadata-forcing same-type
  constraints. **Both PASS** (compile clean, run clean, exit 0).
- **v2–v5 (simplified-Tagged single-file + 2/3/4-module splits)** —
  all **PASS** on 6.3.2.

The conclusion across all five reduction shapes plus Arc 3's
nine-candidate `Tagged.swift` single-file bisection: *the bug is not
reproduced by any single-file or multi-module shape we tried*. The
"bug requires production `Tagged_Primitives.Tagged` symbol with its
production module structure" claim is now **strongly supported** —
not just consistent with prior evidence but empirically tested
against the strongest single-file approximation we could fit.

**Remaining caveat** (per [`ISSUE-026`] coverage-scope discipline):
v1's Trigger B drops the *specific protocol identities* used by
production `.advance(within:)` — `Ordinal.\`Protocol\``,
`Carrier.\`Protocol\`<Cardinal>`, `Cardinal` — because inlining them
would exceed a reasonable single-file budget (~200 lines). If the bug
is gated by those specific protocol identities rather than by the
same-type-constraint *shape* my Trigger B captures, that cell remains
untested. Pursuing a Trigger C with full protocol-identity
scaffolding was orchestrator-decided 2026-05-23 to be diminishing
returns (the resolution path per [`ISSUE-008`] is "wait for the
Swift 6.5 release"; further reduction is not load-bearing for the
resolution decision).

The reproducer below preserves `import Tagged_Primitives` (with
`Ordinal_Primitives` / `Cardinal_Primitives` for the
`.advance(within:)` extension and the `Cardinal` Underlying), per
[`ISSUE-002`]'s "If the issue requires SwiftPM" branch.

### Standalone executable

```bash
swift run swift-issue-tagged-noncopyable-atomic-metadata-crash-Repro
# on Apple Swift 6.3.2 (Xcode 26.4.1):  killed by signal 11; exit 139
# on Swift 6.4-dev nightly 2026-03-16-a+:  prints "result = 0"; exit 0
```

The executable source is [`Sources/Reproducer/main.swift`](Sources/Reproducer/main.swift)
(13 statements, ~33 lines). On the buggy toolchain the kernel kills
the process at `cursor.advance(within: count)`; on the fixed toolchain
the line returns cleanly and the program prints `result = 0`.

### Swift Testing harness

[`Tests/Reproducer.swift`](Tests/Reproducer.swift) wraps the same
buggy call in
`withKnownIssue("…", when: { compiler<6.5 })`. The `when:` predicate is
`#if compiler(<6.5)` — true on shipping Xcode (6.3.x), false on the
6.5-dev nightly stream where the bug is fixed. The semantics:

- On Swift 6.3.x: process SIGSEGVs inside the
  `withKnownIssue` block. SwiftTesting never gets a chance to register
  the known issue (signal kills the process); the CI per-issue matrix's
  macOS leg reports signal 11. That signal-11 IS the bug-fired signal;
  `withKnownIssue` is documentation of intent for human readers.
- On Swift 6.5+: `when:` returns false, the wrapper is bypassed, and the
  embedded `#expect(result.underlying.rawValue == 0)` runs as a regular
  assertion. The test goes green via the regular path.
- If the bug returns on Swift 6.5+: in-process call SIGSEGVs outside
  any `withKnownIssue` wrapper; CI reports signal 11 → regression
  detection.

For SIGSEGV bugs `withKnownIssue` can't deliver the "green → red on fix"
flip semantics the Issues convention prefers (the kernel kills the test
runner before SwiftTesting can record a known issue). The convention is
preserved structurally — the wrapper is present and accurately describes
the expected pattern — but the operational fix-detection mechanism is
the CI per-issue matrix's per-leg signal-11 vs exit-0 outcome, not the
red flip.

---

## Workaround (not landed)

The 2026-05-22 round of typed-wrapper fixes (`Ordinal.AtomicPosition<Tag>`
and bare-Underlying Dictionary key forms) was REVERTED on 2026-05-23 by
orchestrator decision (commits `e46b3b7` / `106d914` / `44ab1f8` /
`b77a4f03` on swift-ordinal-primitives, swift-executors, swift-kernel,
swift-io respectively) on the grounds that the typed-wrapper pattern
degraded the typed approach at the storage layer rather than fixing the
cause. The three handoff-flagged packages (swift-executors,
swift-threads, swift-io) currently SIGSEGV at test time on Apple Swift
6.3.2.

Per [`ISSUE-008`] the appropriate workaround for "fixed in dev, not in
Xcode" is to apply and document — but the orchestrator's standing
correctness preference here (memory entry
an internal feedback note) takes precedence over the
short-term unblock. Resolution is to wait for the Swift 6.5 release,
which will carry the fix to all consumers.

---

## Upstream status and process-document consolidation (2026-07-30)

This section consolidates the durable facts from five process-draft
documents that previously lived beside this README
(`SIBLING-COMMENT-DRAFT.md`, `AUDIT-REPORT.md`,
`BACKPORT-REQUEST-DRAFT.md`, `REVIEWED-BACKPORT-REQUEST.md`,
`REVIEWED-SIBLING-COMMENT.md`); the drafts themselves are workflow
artifacts, removed under Issues#79 with their content preserved in git
history at the removing commit's parent.

**Upstream links, re-verified 2026-07-30:**

| Link | State (2026-07-30) | Role |
|---|---|---|
| [swiftlang/swift#74303](https://github.com/swiftlang/swift/issues/74303) | open | parent family issue (`__swift_instantiateConcreteTypeFromMangledName` null return); intended sibling-comment target |
| [swiftlang/swift#69615](https://github.com/swiftlang/swift/issues/69615) | open | related family member (`TypeLookupError` from `getTypeByMangledNameInContext`) |
| [swiftlang/swift#74333](https://github.com/swiftlang/swift/issues/74333) | closed (completed) | NOT a duplicate of #74303 — closed via PR #74604; the audit (C-22) corrected the earlier "closed dupe" claim |
| [swiftlang/swift PR #87066](https://github.com/swiftlang/swift/pull/87066) | merged (2026-02-10) | carries `bc44d42f11` (+14/−0, `lib/Demangling/Demangler.cpp`: `'j'`/`'J'` inverse-assoc demangler cases); on `release/6.4.x` and `main`, absent from `release/6.3`/`6.3.1` |
| [swiftlang/swift#89389](https://github.com/swiftlang/swift/issues/89389) | open | our filed `[release/6.3]` backport request for `bc44d42f11` — **withdrawn in substance** by the 2026-05-28 codegen correction above (`bc44d42f11` would not fix 6.3-compiled code); any upstream state change there is principal-gated |

**Durable audit conclusions (from the 2026-05-23 pre-post audit, 27
claims verified):**

- The fix-identification chain held: PR #87066 / commit `bc44d42f11` /
  branch containment verified via `gh api compare` (absent from
  `release/6.3` and `release/6.3.1`, ancestor of `release/6.4.x`).
  The 2026-05-28 correction then re-attributed the *defect* from the
  demangler to `SuppressedAssociatedTypes` codegen, superseding the
  backport ask without invalidating the containment facts.
- Cross-platform CI matrix (run
  [26326702012](https://github.com/swift-institute/Issues/actions/runs/26326702012),
  reproducer commit `d85cfcc`): Apple Xcode 6.3.2 macOS arm64 debug —
  CRASH (signal 11); swift.org `swift-6.3.2-RELEASE` Ubuntu x86_64
  release — NO CRASH on the same source tag (`cd8d8ad001`); Windows
  6.3.2 debug — inconclusive (exit 1, no SwiftTesting summary);
  swift.org main nightly Ubuntu release — PASS.
- Surfaced confound: the macOS/Linux legs differ on both platform and
  build configuration, so CI alone does not isolate the discriminator;
  local Apple 6.3.2 testing crashed under both `-Onone` and `-O`.
- Surfaced open question: the macOS-only pattern under one source tag
  suggests the defect locus may be Apple-downstream toolchain
  artifacts rather than `release/6.3` source.
- Snapshot labeling correction (C-19): `2026-03-16-a` and `2026-05-07-a`
  are 6.4-dev, not 6.5-dev; `2026-05-12-a` is 6.5-dev.
- Sibling-comment relationship: whether `bc44d42f11` also closes
  #74303 (DiscordBM `IntBitField<Flag>?`) and #69615 (opaque return
  type) is a determination for the runtime maintainers; the drafts
  deliberately did not claim it.

Any posting, filing, or withdrawal action at swiftlang/swift remains
principal-gated; this section records state only.

## See also

- [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) — full 4-arc convergence record
- `swift-institute/Research/swift-compiler-bug-catalog.md` §A9 — the
  ecosystem-wide canonical entry for this defect
- `swift-foundations/swift-executors/Experiments/sigsegv-repro/` — the
  original SwiftPM reproducer the prior arcs were driven against
  (preserved as-is, untracked)
