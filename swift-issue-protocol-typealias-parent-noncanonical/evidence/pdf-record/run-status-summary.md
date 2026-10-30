# Run-status verification (via `gh`, 2026-07-03)

All statuses re-verified directly against GitHub Actions at investigation time
(`gh run view`, `gh api .../actions/jobs/<id>/logs`). Corrections to the initial
brief are called out explicitly — see CHARACTERIZATION.md §Verification Notes.

| # | Run | Repo | Windows job | Status | Notes |
|---|-----|------|-------------|--------|-------|
| 1 | `28640978811` | swift-foundations/swift-pdf | `Windows (Swift 6.3, debug)` (job `84944472858`) | CRASH (X) | `any HTML.View` at `HTML.AnyView.swift:30` `init(_:)`. Matches brief. See `crash-A-swift-pdf-run28640978811.log`. |
| 2 | `28650247696` | swift-foundations/swift-html-render | `Windows (Swift 6.3, debug)` (job `84966288630`) | CRASH (X) | **CORRECTED run ID** (brief cited `28509190314`, which is an unrelated 2026-07-01 ownership-assertion crash in `Async.Channel.Bounded.Sender.Send.swift` — see §Verification Notes). This run, on branch `windows/anyview-thunk-erasure`, head `0112f8d`, shows the real html-render-own crash: `any HTML.View` at `HTML.AnyView.swift:42` `init(_:)`. See `crash-A-html-render-own-run28650247696.log`. |
| 3 | `28653857845` | swift-foundations/swift-html-render | `Windows (Swift 6.3, debug)` (job `84978112214`) | GREEN (✓) | Same branch, head `b179cf5` (post thunk-erasure fix). Windows leg passes; run-level conclusion is `failure` only because of an unrelated docs/DocC job. Matches brief. |
| 4 | `28661306902` | swift-foundations/swift-pdf | `Windows (Swift 6.3, debug)` (job `85002325302`) | CRASH (X) | Build progressed to `[8274/8311]` (matches brief's "~8274/8311"). **Debugger type is `any PDF.HTML.Style.Modifier`, NOT `any HTML.View`** — see §Verification Notes. Crash site: `PDF.HTML.Context.apply(inlineStyle:)` at `PDF.HTML.Context+Rendering.swift:234`. See `crash-B-swift-pdf-run28661306902.log`. |
| 5 | `28665715143` | swift-foundations/swift-pdf | `Windows (Swift 6.4, debug) — any-HTML.View 6.4-fix proof` (job `85016815771`) | **QUEUED at investigation time** (2026-07-03T14:07Z, re-checked 14:1x — still not completed) | Not yet resolved. Do not treat the Swift 6.4 fix as CI-confirmed for swift-pdf until this job reports `success`. |

Local reproduction on the installed macOS `swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a`
(+assertions, Swift 6.5-dev, `4d0c97fa5b05711`) was attempted for manifestation B
(`swift build --build-tests -c debug` in `swift-pdf-html-render`) but did not reach
`PDF.HTML.Context+Rendering.swift`: the build aborted earlier on an unrelated,
pre-existing SIL verifier failure in `swift-parser-primitives`
(`Parser.Protocol.body` — "public/package/shared function must have a body").
The brief's claim that this bug "is NOT reproducible on local swift.org 6.4-dev /
6.5-dev snapshots" is therefore CARRIED OVER, UNVERIFIED by this session — it was
not independently confirmed here.
