# Evidence

Copied from `swift-institute/Experiments/sequence-map-builder-consuming-bug` at
commit `f1c4db4d390c12af5ec454dfb506feaa4ec5e841`, plus the 6.4.2 recheck.

| File | What it is |
|------|------------|
| `original-main.swift` | The experiment's file, with its V1–V4 header and findings from 6.3.2. It is committed in the workaround state (`var _base`, V1 commented out), so it compiles. |
| `original-Package.swift.txt` | The experiment's SwiftPM manifest and its feature flags. |
| `control-var-field.swift` | `../Sources/Reproducer/Bug.swift.txt` with `Builder._base` changed from `let` to `var`. Compiles cleanly with the same flags; used as the probe's "absent" control. |
| `diagnostic-6.4.2.txt` | The bare `swiftc -c` command and its output on Swift 6.4.2 (Xcode 27.2), exit 1. |

The Swift sources kept here verbatim are stored as `.swift.txt`, so the repository formatter and linter never rewrite them: `original-main.swift.txt`. Scripts and notes in this folder name them by their original `.swift` names; rename a file back to rerun it.
