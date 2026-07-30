# Issues

Minimal Swift packages reproducing toolchain and compiler bugs encountered
while developing the [Swift Institute](https://swift-institute.org)
ecosystem — the institute's own defect records: each entry carries the
reduced reproducer, evidence captures, duplicate differentiation against
upstream reports, and the verified workaround the ecosystem ships.

## Overview

Each `swift-issue-*/` subdirectory holds one minimum reproducer of a
single Swift toolchain or compiler bug. Reproducers are reduced to the
minimum trigger: no package-internal types, no transitive dependencies,
no special swiftSettings beyond what the bug requires.

When a bug catalog entry says "this code miscompiles on Linux release,"
the issue reproducer proves it — runnable from `swift test` (or directly
via the standalone executable) and verified by CI on every supported
platform.

The companion research repository is at
[swift-institute/Research](https://github.com/swift-institute/Research).
The companion experiments repository is at
[swift-institute/Experiments](https://github.com/swift-institute/Experiments).

## Per-Issue Convention

Every `swift-issue-*/` subdirectory follows this steady-state layout.
The convention was established by
`swift-issue-pointer-arithmetic-linux-miscompile/` and applies to every
subsequent issue.

```
swift-issue-<topic>/
├── README.md                  — bug summary, trigger characterization, workaround
├── INVESTIGATION-ARC.md       — (optional) multi-round convergence record
├── ISSUE-<NNNN>-COMMENT.md    — (optional, historical) extended characterization notes from earlier entries
├── Tests/
│   └── Reproducer.swift       — Swift Testing harness, withKnownIssue flip semantics
├── Sources/
│   └── Reproducer/
│       └── main.swift         — standalone exit-code reproducer
└── evidence/                  — (optional) bisection artifacts from investigation
    ├── README.md
    └── …
```

Each issue declares exactly two SwiftPM targets in the root
`Package.swift`:

```swift
.testTarget(
    name: "swift-issue-<topic>-Tests",
    path: "swift-issue-<topic>/Tests"
),
.executableTarget(
    name: "swift-issue-<topic>-Repro",
    path: "swift-issue-<topic>/Sources/Reproducer"
),
```

Target names match the issue directory so `swift test --filter
<issue-dir-underscored>` selects exactly this issue's tests via substring
match on the module-name prefix (SwiftPM converts hyphenated target
names to underscored module identifiers).

### Two harnesses per issue

- **`Tests/Reproducer.swift`** — Swift Testing. Wraps the bug's
  minimum trigger in `withKnownIssue("swiftlang/swift#NNNN",
  when: { <platform-precondition> })`. **Green** while the bug
  fires on the configured platforms (current toolchain state);
  flips **red** the moment the upstream fix lands and the bug
  stops firing. The red flip IS the fix-detection signal — captured
  by the weekly nightly CI cron.
- **`Sources/Reproducer/main.swift`** — standalone executable.
  `exit(0)` on no-bug-fired, `exit(1)` on bug-fired. Covers codegen
  surfaces that the SwiftPM test runner may mask on some
  toolchains. Useful for ad-hoc probing against a specific
  toolchain image (e.g., `docker run --rm swift:6.3 swift run
  swift-issue-<topic>-Repro`).

### Why `withKnownIssue` and not `.disabled(if: …)`

`.disabled(if: …)` is **silent** when upstream lands a fix — no
signal, no PR-trigger, no detection. `withKnownIssue` flips red the
moment the bug stops firing on the configured platform, which IS the
upstream-fix detection mechanism. Skipping via `.disabled` alone is a
regression of detection capability and is forbidden per the per-issue
convention.

### Adding a new issue

1. Create `swift-issue-<topic>/` at the repo root.
2. Write the bug `README.md` + (optional) `INVESTIGATION-ARC.md`.
3. Author `Tests/Reproducer.swift` and `Sources/Reproducer/main.swift`.
4. Add the two targets to the root `Package.swift`.
5. Push. CI auto-includes the new issue via `enumerate-issues`'s
   `ls -d swift-issue-*/` — zero CI maintenance.

## Building

Each issue is a target in this repo's root `Package.swift`. Clone and
test from the repo root:

```bash
git clone https://github.com/swift-institute/Issues.git
cd Issues
swift test                                                             # all issues
swift test --filter swift_issue_<topic>                                # one issue
swift run swift-issue-<topic>-Repro                                    # standalone executable
```

Requires Swift 6.3 or newer.

## CI

Continuous integration is per-issue × per-platform.

- A single `enumerate-issues` job emits the `swift-issue-*/`
  directory list as a JSON array.
- A `per-issue` matrix job consumes that list and calls the
  centralized
  [`swift-institute/.github`](https://github.com/swift-institute/.github)
  reusable workflow once per issue with `test-filter: <issue-dir>` —
  one full reusable invocation (macOS / Linux release / Linux nightly
  / Windows + format + lint + advisory linters) per issue. Each
  `(issue × reusable-job)` leg is its own status check.
- `fail-fast: false` — one issue's red leg never cancels sibling
  issues' legs.
- Weekly cron at Monday 06:00 UTC re-runs the matrix. The reusable's
  `linux-nightly` leg (`swiftlang/swift:nightly-main-jammy`) is where
  `withKnownIssue` flips red on upstream-fix-landing.
- No `ci-ok` aggregator-gating. The Issues repo's branch protection
  doesn't reference `ci-ok`; per-issue test legs are the actionable
  signals; one red issue does not block merges.

For an issue reproducer, **a permanently-red Linux release leg is the
bug's running evidence**. When the upstream fix lands and the
`withKnownIssue` block stops firing on `nightly-main-jammy`, that's the
signal to close the issue and either remove the reproducer or relocate
it as a regression fixture.

## License

[Apache 2.0](LICENSE.md).
