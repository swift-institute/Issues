# Evidence

Copied from `swift-institute/Experiments` at commit
`f1c4db4d390c12af5ec454dfb506feaa4ec5e841`. Every `.swift` file has a `.txt`
suffix so it is not compiled or linted as part of the Issues package. `.build`
directories were not copied.

| Path | What it is |
|---|---|
| `copytoborrow-actor-state-mutex-miscompile/` | The 87-line two-module reproducer and its package. Its header records "STILL PRESENT" on 6.3.1 (2026-04-17 and 2026-04-30), about 50/100 iterations wrong, and the workaround. |
| `swift-copytoborrow-bug/` | The full-context original, cut from swift-io's `IO.Event.Selector` shutdown path. Not rebuildable: its `Package.swift` points at `../swift-foundations/…` and `../swift-primitives/…` paths that no longer exist. Its result is recorded in `Experiments/_index.json`: "SUPERSEDED … by copytoborrow-actor-state-mutex-miscompile (87-line minimal repro)", and in the Research catalog §A6 as failing 100/100 on 6.3.1. |
| `actor-state-inline-fallback-repro/` | Negative control. Its header: "NOT REPRODUCED", 0 stale reads in 1000 iterations per scenario on 6.3.1. It rules out the inline-executor-fallback and cross-thread visibility theories. |
| `runs-6.4.2-macos.log` | Commands and results on Apple Swift 6.4.2, macOS 27.2 arm64, 2026-10-27: the failing build and each one-change control. |
| `asan-6.4.2-macos.log` | The failing build with `-sanitize=address`: `heap-use-after-free`. The same build with the pass disabled in the client runs clean. |
