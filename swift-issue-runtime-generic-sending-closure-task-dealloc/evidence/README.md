# Evidence

| File | What it is |
|---|---|
| `original/` | The Experiments folder `silgen-thunk-noncopyable-sending-capture/` at commit `f1c4db4d390c12af5ec454dfb506feaa4ec5e841`, in full: `Package.swift` (as `Package.swift.txt`, with the nine original settings) and `Sources/main.swift` (as `main.swift.txt`, with its 6.3.1 SILGen record in the header). |
| `variant-copyable-payload.swift` | The original program with `Payload` made copyable. Still aborts at `-Onone`: `~Copyable` is not needed. |
| `variant-noncopyable-typed-throws.swift` | A first reduction that keeps `~Copyable`, `Optional.take()` and typed throws. Aborts. |
| `variant-inferred-closure.swift` | The reproducer with the closure type inferred. Aborts. |
| `variant-int-value.swift` | The reproducer with `Value = Int`. Aborts. |
| `control-synchronous.swift` | The reproducer made synchronous. Runs clean. |
| `control-no-sending.swift` | The reproducer without `sending` on the closure parameter. Prints `hello`, exits 0. The probe's "absent" control. |
| `control-plain-resume-param.swift` | The reproducer without `sending` on `resume`'s parameter. Runs clean. |
| `control-non-generic.swift` | The reproducer with `One` made non-generic. Runs clean. |
| `macos-6.4.2-run.txt` | Apple Swift 6.4.2, macOS arm64, 2026-10-27: the original file compiles (no SILGen crash) and its program aborts at `-Onone`. The reproducer, the controls and the variants are built at `-Onone` and `-O` under `-strict-memory-safety -warnings-as-errors`, then run. |
| `macos-6.4.2-lldb-backtrace.txt` | The reproducer's abort under lldb: `swift_task_dealloc` called from `App.main()`. |

The Swift sources kept here verbatim are stored as `.swift.txt`, so the repository formatter and linter never rewrite them: `variant-copyable-payload.swift.txt`, `variant-int-value.swift.txt`, `variant-inferred-closure.swift.txt`, `control-synchronous.swift.txt`, `variant-noncopyable-typed-throws.swift.txt`. Scripts and notes in this folder name them by their original `.swift` names; rename a file back to rerun it.
