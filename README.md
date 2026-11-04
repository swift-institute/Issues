# Issues

Use this repository when you hit what looks like a bug in the Swift toolchain, SwiftPM, swift-format, swift-syntax, swift-foundation or Xcode while working on the Institute. Open it here first, with the "Toolchain bug" issue form. Each `swift-issue-<topic>/` folder holds one reduced reproducer and its notes, as a test target and an executable target in the root `Package.swift`. For routing, reduction, the toolchain matrix, duplicate search and upstream formats, read [UPSTREAM-PROCEDURE.md](UPSTREAM-PROCEDURE.md). The reducer and the gate are in [Tooling/](Tooling).

## Laws

- A bug goes upstream only after `issue-check` passes and Coen says yes to that filing.
- `issue-check` decides the `upstream-ready` and `upstream-filed` labels. Nobody applies them by judgment.
- A reproducer holds only what the bug needs: no package-internal types, no transitive dependencies, and no settings beyond what triggers it.
- A reproducer's test wraps the trigger in `withKnownIssue`, so it stays green while the bug fires and turns red when the fix lands. It never uses `.disabled(if:)`, which stays silent when upstream fixes the bug.
- A test turning red on a newer toolchain means the bug may be fixed. Confirm it, then close the issue and remove the reproducer or keep it as a regression fixture.
- A reproducer's `main.swift` exits with 1 when the bug fires and 0 when it doesn't, because the test runner can mask some code generation bugs.
