# Issues

Use this repository when you hit what looks like a bug in the Swift toolchain, SwiftPM, swift-format, swift-syntax, swift-foundation or Xcode while working on the Institute. Open it here first, with the "Toolchain bug" issue form. The issue is the record. A `swift-issue-<topic>/` folder holds only the code that shows the bug still fires: an `ISSUE` file with the issue's number, a `Tests/` test, and optionally a `Sources/Reproducer/` executable. The root `Package.swift` finds the folders on its own. For routing, reduction, the toolchain matrix, duplicate search and upstream formats, read [UPSTREAM-PROCEDURE.md](UPSTREAM-PROCEDURE.md). The reducer and the gate are in [Tooling/](Tooling).

## Laws

- A bug goes upstream only after `issue-check` passes and Coen says yes to that filing.
- `issue-check` decides the `upstream-ready` and `upstream-filed` labels. Nobody applies them by judgment.
- `issue-check --layout`, run in CI, checks every folder: its `ISSUE` file names an open issue, its test calls `withKnownIssue`, and it holds no notes (`*.md`, `evidence/`). Notes go on the issue.
- A reproducer holds only what the bug needs: no package-internal types, no transitive dependencies, and no settings beyond what triggers it.
- A reproducer's test wraps the trigger in `withKnownIssue`, so it stays green while the bug fires and turns red when the fix lands. It never uses `.disabled(if:)`, which stays silent when upstream fixes the bug.
- A code generation bug that the test runner can mask also gets `Sources/Reproducer/main.swift`. It exits with 1 when the bug fires and 0 when it doesn't.
- CI runs each folder's test by itself on Linux, macOS and Windows. A push runs the folders it changed. Every Monday all of them run, plus Linux nightly in the same release configuration.
- A red leg is evidence, not a broken repository: there is no `ci-ok`, and one folder never blocks another. A red leg means the bug stopped firing or changed. Confirm that, then close the issue and delete the folder. Git history keeps it.
- An open toolchain record with no folder carries `needs-reproducer` until it gets one.
