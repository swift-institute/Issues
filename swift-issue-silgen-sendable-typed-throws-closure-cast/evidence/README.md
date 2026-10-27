# Evidence

| File | What it is |
|---|---|
| `original/` | The Experiments folder `silgen-sendable-typed-throws-closure-cast/` at commit `f1c4db4d390c12af5ec454dfb506feaa4ec5e841`: `Package.swift` (as `Package.swift.txt`, with the nine original settings) and `Sources/main.swift` (as `main.swift.txt`, with its 6.3.1 record in the header). |
| `control-let-bound-closure.swift` | The workaround: the closure bound to a typed `let`, then passed. Compiles. The probe's "absent" control. |
| `control-untyped-throws.swift` | `throws(TestError)` replaced by untyped `throws`. Compiles. |
| `macos-6.4.2-run.txt` | Reproducer (no flags), the original file with all nine settings, and both controls, on Apple Swift 6.4.2, macOS arm64, 2026-10-27. |

The Swift sources kept here verbatim are stored as `.swift.txt`, so the repository formatter and linter never rewrite them: `control-untyped-throws.swift.txt`. Scripts and notes in this folder name them by their original `.swift` names; rename a file back to rerun it.
