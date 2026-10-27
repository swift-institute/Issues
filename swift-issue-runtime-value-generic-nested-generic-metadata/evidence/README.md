# Evidence

| File | What it is |
|---|---|
| `original/` | The Experiments folder `value-generic-nested-generic-metadata-crash/` at commit `f1c4db4d390c12af5ec454dfb506feaa4ec5e841`: its README, `Package.swift` (as `Package.swift.txt`) and `Sources/main.swift` (as `main.swift.txt`, with the full A/B record in its header). |
| `control-type-generic-parent.swift` | The parent made type-generic (`Link<N>`). Prints `main.Link<Swift.Int>.Node<Swift.Int>` and exits 0. The probe's "absent" control. |
| `control-non-generic-nested.swift` | The nested type made non-generic. Prints `main.Link<1>.Node` and exits 0. |
| `macos-6.4.2-run.txt` | Reproducer and both controls at `-Onone` and `-O` on Apple Swift 6.4.2, macOS arm64, 2026-10-27. |
| `macos-6.4.2-lldb-backtrace.txt` | The crashing frame under lldb on the same toolchain. |

Later toolchain results come from the recheck workflow's comments on
swift-institute/Issues#105, summarized in the entry README.
