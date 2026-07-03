# `isActuallyCanonicalOrNull()` abort mangling the debugger type of a Copyable existential during Windows 6.3.3 (+Asserts) debug-info IRGen

> **STAGED terminal record** (not filed upstream — swiftlang filing does not exist
> as a step per [ISSUE-008] standing policy). `swift-institute/Issues` is the only
> destination. Sibling of catalog §A20 (`Mangler::verify`, SILGen witness-name
> round-trip) and §A21 (`getMangledName`, IRGen debug-info of a named local) — same
> **+Asserts-only, Windows-CI-gating, debug-info-mangling** family, but a
> **distinct assertion** (`isActuallyCanonicalOrNull` at `Type.h:421`, not
> `Mangler.cpp:176` or `IRGenDebugInfo.cpp:1098`) and a distinct trigger shape
> (an `any P` existential formed at an IRGen-debug-info-emitting site, not a
> witness name or a sugared typealias). Candidate catalog slot: §A24.

## Classification

**ICE / Crash** — compiler assertion abort (`abort()`, signal/exception) during
**IR generation of debug info** for a source-level existential (`any P`), while
handling `IRGenRequest`. Surfaces only on the **Windows CI leg**
(`windows-latest` runner, `swift.org` `swift-6.3.3-RELEASE-windows10`, which
resolves to the **`6.3.3+Asserts`** toolchain, **debug** config, `-g`). Green on
macOS CI (Xcode 26.4, NoAsserts — the assert cannot fire) and Linux CI (release
config — different debug-info path).

## Environment

| | |
|---|---|
| **Crashes on** | Swift 6.3.3 (`swift-6.3.3-RELEASE`), `6.3.3+Asserts` toolchain, Windows CI leg (`ci / matrix / Windows (Swift 6.3, debug)`), `-Onone -g` |
| **Green on** | macOS CI (Xcode 26.4, iOS/tvOS/watchOS/macOS legs, NoAsserts); Linux CI (`swift:6.3` release) |
| **Config** | `-Onone -g`, `-debug-info-format=dwarf`; crash is in IRGen debug-info emission, not SILGen or SIL optimization |
| **Repos** | `swift-foundations/swift-pdf`, `swift-foundations/swift-html-render`, `swift-foundations/swift-pdf-html-render` (dependency of swift-pdf, resolved via `.build/checkouts`) |

## Observed

```
Assertion failed: isActuallyCanonicalOrNull() && "Forming a CanType out of a non-canonical type!",
file C:\Users\swift-ci\jenkins\workspace\swift-6.3-windows-toolchain\swift\include\swift/AST/Type.h, line 421
```

followed by a stack dump whose decisive frames are always the same three-frame shape:

```
3.  While evaluating request IRGenRequest(IR Generation for file "<...>.swift")
4.  While emitting IR SIL function "<mangled-name>".
     for '<function>' (at <file>:<line>:<col>)
5.  While mangling type for debugger type 'any <Protocol>'
```

Two verified manifestations share this exact assertion and frame shape but differ
in **which** `any P` existential is being mangled and **how** it is formed:

### Manifestation A — `any HTML.View` (RESOLVED)

- **Site**: `HTML.AnyView.init<T: HTML.View>(_ base: T)`, `HTML.AnyView.swift`
  (swift-html-render, module `HTML_Rendering_Core`).
- **Debugger type**: `'any HTML.View'`.
- **Mechanism**: `HTML.View` refines the move-only `Render.View` (`~Copyable`,
  swift-render-primitives) with a **self-recursive** constraint —
  `public protocol View: Render.View where Body: HTML.View`. The Copyable
  existential `any HTML.View` of this `~Copyable` + recursive protocol is
  non-canonical for the 6.3.3 Windows +Asserts debug-info mangler.
- **Fix (APPLIED & VALIDATED)**: eliminate every explicit `any HTML.View` site —
  `HTML.AnyView` erased through a captured render-thunk closure instead of
  boxing `any HTML.View` (`swift-html-render` commit `100bd63`); swift-css
  layout helpers changed `var result: any HTML.View` to a concrete
  `HTML.AnyView` accumulator (5 files); swift-markdown-html-render's
  `HTML.Builder` overloads changed `any HTML.View` returns to `some HTML.View`.
  Verified CRASH → GREEN on the Windows leg (see §Evidence run 2 → run 3).

### Manifestation B — `any PDF.HTML.Style.Modifier` (UNRESOLVED)

- **Site**: `PDF.HTML.Context.apply(inlineStyle:)`,
  `PDF.HTML.Context+Rendering.swift:234` (swift-pdf-html-render, module
  `PDF_HTML_Rendering`).
- **Debugger type**: `'any PDF.HTML.Style.Modifier'`.
- **Mechanism**: `apply(inlineStyle property: Any) -> Bool` unwraps an
  `Optional` via `Mirror`, then does two **ordinary conditional downcasts**:

  ```swift
  // PDF.HTML.Context+Rendering.swift:267
  if let modifier = unwrapped as? any PDF.HTML.Style.Modifier {
      ...
      modifier.apply(to: &pdf, configuration: configuration)
      handled = true
  }
  // PDF.HTML.Context+Rendering.swift:283
  if let htmlModifier = unwrapped as? any PDF.HTML.Style.Context.Modifier {
      htmlModifier.apply(to: &self)
      handled = true
  }
  ```

  `PDF.HTML.Style.Modifier` (`PDF.HTML.Style.Modifier.swift:21`) is a **plain
  Copyable, non-recursive** protocol — `public protocol Modifier { func
  apply(to context: inout PDF.Context, configuration: PDF.HTML.Configuration) }`
  — nested inside `extension PDF.HTML.Style { ... }`. It has **no** `~Copyable`
  suppression and **no** self-recursive `Body`-style constraint. Yet forming
  its existential at this debug-info-emitting site trips the identical
  `isActuallyCanonicalOrNull` assertion.
- **Status**: UNRESOLVED. No fix attempted in this investigation; see
  §Verification Notes for why the Manifestation-A fix pattern does not
  transfer directly (this call is a runtime dynamic dispatch over a
  heterogeneous `Any`-typed style-property list, not a static generic).

## Evidence

Full run/job verification table, corrected run IDs, and the local-reproduction
attempt are in `evidence/run-status-summary.md`. Trimmed log excerpts (assertion
+ decisive frames, giant `Program arguments` line elided):

- `evidence/crash-A-swift-pdf-run28640978811.log` — swift-pdf, `any HTML.View` at `HTML.AnyView.swift:30`, run `28640978811`, job `84944472858`.
- `evidence/crash-A-html-render-own-run28650247696.log` — swift-html-render's own crash, `any HTML.View` at `HTML.AnyView.swift:42`, run `28650247696`, job `84966288630` (branch `windows/anyview-thunk-erasure`, head `0112f8d`, pre-fix).
- `evidence/crash-B-swift-pdf-run28661306902.log` — swift-pdf, `any PDF.HTML.Style.Modifier` at `PDF.HTML.Context+Rendering.swift:234`, run `28661306902`, job `85002325302`, build progressed to `[8274/8311]`.

GREEN confirmation: run `28653857845` (job `84978112214`), same branch as the
html-render-own crash, head `b179cf5` (post thunk-erasure fix) — Windows leg
passes (`✓`); overall run conclusion is `failure` only from an unrelated
DocC-archive job.

Pending: run `28665715143` (job `85016815771`) — swift-pdf-owned advisory
`Windows 6.4 proof` workflow (`.github/workflows/windows-6.4-proof.yml`),
`windows-latest` + Swift 6.4, `continue-on-error: true`. **Status at
investigation time: QUEUED** — not yet resolved. Re-check before treating the
6.4 fix as CI-confirmed for swift-pdf.

## Verification Notes — corrections to the inherited narrative

This investigation was briefed with a root-cause narrative (also baked into
`swift-pdf/.github/workflows/windows-6.4-proof.yml`'s header comment) claiming
the *entire* bug — including the still-unresolved final blocker — is `any
HTML.View` forming **implicitly** from legitimate `<H: HTML.View>` generic
constraints (`PDF.Document.init<H: HTML.View>` at
`swift-pdf-html-render/Sources/PDF HTML Rendering/PDF.Document+HTML.swift:26`,
and an entry-point `render<H: HTML.View>` in `PDF.HTML+EntryPoints.swift`), and
that `PDF.HTML.Context+Rendering.swift` "has NO explicit `any HTML.View`."

Verified against the actual CI log (run `28661306902`, job `85002325302`,
fetched via `gh api repos/swift-foundations/swift-pdf/actions/jobs/85002325302/logs`)
and the current source (`PDF.HTML.Context+Rendering.swift:234-294`, `git log`
shows no `HTML.View` reference anywhere in this file's history), **this claim
does not hold**:

1. The debugger type in the crash frame is `'any PDF.HTML.Style.Modifier'`,
   never `'any HTML.View'` — confirmed across all 24 repeated assertion
   instances in the log (WMO batch retries), zero occurrences of `HTML.View`.
2. The file **does** contain explicit existential formation — two conditional
   downcasts to `any PDF.HTML.Style.Modifier` (line 267) and `any
   PDF.HTML.Style.Context.Modifier` (line 283) — contradicting "no explicit
   `any HTML.View`" (true only because the wrong protocol was assumed).
3. `<H: HTML.View>` generic constraints do exist in swift-pdf-html-render
   (`PDF.Document+HTML.swift:26`, `PDF.HTML+EntryPoints.swift`) and are real,
   but grepping their `git log` and the crash frame shows they are **not
   implicated** in this crash at all.

**Implication**: the compiler bug is broader than "Copyable existential of a
`~Copyable` + self-recursive protocol" (Manifestation A's mechanism). A plain
Copyable, non-recursive, ordinarily-cast protocol existential
(`PDF.HTML.Style.Modifier`) triggers the identical `isActuallyCanonicalOrNull`
assertion at the identical `Type.h:421` site under the identical "mangling type
for debugger type" IRGen frame. The common factor across both manifestations
appears to be: **an `any P` existential, for a namespaced/nested institute
protocol, formed at a site whose debug-info record IRGen must emit** — not
specifically `~Copyable` refinement or recursion. Consequently, even a
hypothetical (unattempted, out of scope, and previously "principal-rejected as
unremovable" per the brief) removal of the `<H: HTML.View>` generic entry
points would **not** fix Manifestation B, since those generics are not its
trigger.

A separate run-ID correction: the brief's citation of `28509190314` as
"swift-html-render own Windows crash" is **wrong** — that run (a 2026-07-01
heritage-merge commit, `ea344b6`) fails on an unrelated SILGen ownership
assertion (`value->getOwnershipKind() == OwnershipKind::None`,
`ManagedValue.h:208`) in `swift-async-primitives`'
`Async.Channel.Bounded.Sender.Send.swift:42` — no `isActuallyCanonicalOrNull`,
no `HTML.AnyView`, no `HTML.View` anywhere in that log. The correct run
demonstrating html-render's own pre-fix `any HTML.View` crash is `28650247696`
(job `84966288630`, branch `windows/anyview-thunk-erasure`, head `0112f8d`).

The brief's claim that the bug is "NOT reproducible on local swift.org 6.4-dev
/ 6.5-dev snapshots" was **not independently verified** by this session — see
`evidence/run-status-summary.md` for the attempted-but-blocked local
reproduction (an unrelated pre-existing SIL verifier crash in
swift-parser-primitives prevented the build from reaching the affected module
on the installed `swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a` +Asserts toolchain).

None of this changes the top-line disposition (§Resolution) — both
manifestations are the same class of Windows-6.3.3-+Asserts-only compiler
defect and the workaround shape (eliminate the crashing existential at each
site, defer to the ecosystem 6.4 move for confirmation) is consistent — but the
specific causal chain claimed for Manifestation B was incorrect and is
corrected here per house verification discipline (cite the log, don't inherit
the narrative).

## Resolution

**Manifestation A — APPLIED & VALIDATED.** Eliminated every explicit `any
HTML.View` across the html-render/css/markdown-html-render cohort (thunk
erasure, concrete accumulators, `some HTML.View` opaque returns). Windows CI
verified CRASH → GREEN (`28650247696` → `28653857845`).

**Manifestation B — DEFERRED, principal-accepted as an upstream compiler
defect.** No workaround applied to `apply(inlineStyle:)` in this
investigation — the Manifestation-A fix shape (replace a *static* generic
existential-boxing call site with a concrete eraser) does not obviously
transfer to this call site's *runtime* dynamic-dispatch-over-heterogeneous-`Any`
shape, and no alternative was attempted or validated. swift-pdf's final Windows
integration leg (`ci / matrix / Windows (Swift 6.3, debug)`) remains red on this
one module pending either (a) a validated structural fix to
`apply(inlineStyle:)`'s existential formation (not attempted here), or (b) the
ecosystem's move to Swift 6.4, which the swift-pdf-owned advisory proof job
(`windows-6.4-proof.yml`, run `28665715143`, **QUEUED at investigation time**)
is intended to empirically confirm once it completes.

Per [ISSUE-008]: terminal dossier (this) + no upstream filing. The compiler bug
itself is UNFIXED on the 6.3 line for either manifestation's trigger shape; the
6.4-fixes-it claim is PENDING CI CONFIRMATION, not yet proven for this
ecosystem's build.

## Cross-references

- Catalog §A20 (`swift-issue-vector-iterable-materializing-mangler-verify`) — sibling class, `Mangler::verify` at SILGen.
- Catalog §A21 (`swift-issue-dimension-axis-typealias-windows-asserts-ice`) — sibling class, `getMangledName` at IRGen debug-info.
- Catalog §A22 (`swift-issue-algebra-field-typed-throws-windows-asserts-ice`) — sibling class, `hasErrorResult()` SIL function-type invariant.
- Catalog §A23 (`swift-issue-file-system-streaming-write-ownership`) — unrelated mechanism (CopyPropagation borrow-scope), also was blocking a swift-pdf release; FIXED on 6.5-dev.
- `swift-foundations/swift-html-render` commit `100bd63` — Manifestation A fix.
- `swift-foundations/swift-pdf/.github/workflows/windows-6.4-proof.yml` — advisory proof job; header comment's causal-chain claim is superseded by §Verification Notes above.

## Source

2026-07-03 investigation, dispatched to record the swift-pdf / swift-html-render
/ swift-pdf-html-render Windows 6.3.3 (+Asserts) debug-info-mangler arc in
`swift-institute/Issues`. All run IDs and log excerpts independently
re-verified via `gh run view` / `gh api .../actions/jobs/<id>/logs` against
live GitHub Actions state on 2026-07-03; two factual corrections to the initial
brief are recorded in §Verification Notes.
