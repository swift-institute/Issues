# Evidence

| File | What it is |
|---|---|
| `original/` | The Experiments folder `generic-specializer-sendable-closure-cast-release/` at commit `f1c4db4d390c12af5ec454dfb506feaa4ec5e841`: `Package.swift` (as `Package.swift.txt`, with the nine settings the harness passes) and `Sources/main.swift` (as `main.swift.txt`, whose header holds the Linux assertion text). |
| `control-let-bound-closure.swift` | The workaround: the closure bound to a typed `let`, then passed. The "absent" control for an assertions toolchain. |
| `macos-6.4.2-run.txt` | Reproducer and control at `-O` and `-Onone` on Apple Swift 6.4.2, macOS arm64, 2026-10-27: all clean. Also shows that this compiler has no assertions. |

No crash log of the reduced file exists. The assertion text comes from the
swift-machine-primitives Ubuntu 6.4 release CI job recorded in the original header.
