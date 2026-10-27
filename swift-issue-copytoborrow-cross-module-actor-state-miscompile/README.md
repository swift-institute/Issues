# Swift Issue: CopyToBorrowOptimization miscompiles a cross-module actor call (stale state, use-after-free)

**Upstream:** **NOT FILED.** This directory is the institute's record.

**Classification:** SIL optimizer runtime miscompile, release builds only. The
program is valid. Built with `-O`, a client of an `-O -wmo` library reads an
actor's state that an awaited call has already changed. Under AddressSanitizer
the same build reports `heap-use-after-free`, so the optimizer drops a retain
and the client reads freed memory.

## Minimal reproducer

Two modules, 87 lines in all, no dependencies beyond the standard library's
`Synchronization`:

- `Sources/Reproducer/BugLib.swift.txt`: a `SerialExecutor` class `Loop`, an
  actor `Runtime` with `enum State { case running, shuttingDown }` and a custom
  `unownedExecutor`, a `Selector` struct that forwards `register()` to it, and a
  `~Copyable` `Scope` with a `Mutex<Bool>` field and `consuming func close() async`
  that calls `runtime.shutdown()`.
- `Sources/Reproducer/BugTest.swift.txt`: 100 times, make a `Scope`, keep its
  selector, `await scope.close()`, then `try await sel.register()`. `register()`
  must throw `Err(1)` because the state is `.shuttingDown`.

```bash
cp Sources/Reproducer/BugLib.swift.txt BugLib.swift
cp Sources/Reproducer/BugTest.swift.txt main.swift
xcrun swiftc -O -wmo -swift-version 6 -parse-as-library -module-name BugLib \
    -emit-module -emit-module-path BugLib.swiftmodule -emit-object -o BugLib.o BugLib.swift
xcrun swiftc -O -wmo -swift-version 6 -module-name BugTest -I . main.swift BugLib.o -o BugTest
./BugTest
```

**Actual** (Apple Swift 6.4.2, macOS 27.2 arm64): 100 lines of

```
BUG (0): got id=2, expected 1
```

then `PASS`, which is only the loop's end marker.

**Expected:** no `BUG` line. `register()` sees `.shuttingDown` and throws `Err(1)`.

## Trigger characterization

Each row changes one thing against the failing build. Logs are in
`evidence/runs-6.4.2-macos.log` and `evidence/asan-6.4.2-macos.log`.

| Change | Result on 6.4.2 |
|---|---|
| none (library `-O -wmo`, client `-O -wmo`) | 100/100 wrong |
| library `-O` without `-wmo` | correct |
| library `-Onone` | correct |
| library `-enable-library-evolution` | correct |
| client `-Onone` | correct |
| client `-O` without `-wmo` | 100/100 wrong |
| `-sil-disable-pass=copy-to-borrow-optimization` in the library | 100/100 wrong |
| `-sil-disable-pass=copy-to-borrow-optimization` in the client | correct |
| `Scope` without its `Mutex<Bool>` field | correct |
| `Runtime` without the custom `unownedExecutor` | **segfault** at run time in `DefaultActorImpl::tryLock`; correct with the pass disabled in the client |
| both modules concatenated into one file, `-O -wmo` | correct |
| `-sanitize=address` on both modules | `heap-use-after-free` |
| `-sanitize=address`, pass disabled in the client | correct |

So the library must be optimized as a whole module, which lets
cross-module optimization serialize its bodies. The miscompile happens in the
client, where CopyToBorrowOptimization runs over those inlined bodies. Library
evolution turns cross-module optimization off and the bug with it.

The earlier record (Research catalog §A6, 6.3.1) said disabling the pass in the
library was enough and that a custom executor was required. On 6.4.2 neither
holds: the pass must be off in the client, and without the custom executor the
same build crashes instead of reading stale state.

## Flakiness

The 6.3.1 record says about 50 of 100 iterations went wrong. On 6.4.2 every
iteration of every run is wrong. The harness still runs the client 5 times
(500 iterations) and reports the bug if any iteration is wrong, so a partial
rate is caught too.

## Toolchains

| `swiftc --version` | Result |
|---|---|
| Apple Swift 6.3 (Xcode 26) | wrong, recorded in the experiment header |
| Apple Swift 6.3.1 (Xcode 26.4.1), 2026-04-17 and 2026-04-30 | wrong, recorded in the experiment header |
| Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1), macOS 27.2 arm64 | 100/100 wrong, run here 2026-10-27 |

Only macOS has been run. Linux and Windows were not run locally; CI covers them.
No open-source or snapshot toolchain has been run, so the owner (swiftlang vs.
Apple) is not settled yet.

## Workaround

`-Xllvm -sil-disable-pass=copy-to-borrow-optimization` on the client module (in
SwiftPM: `-Xswiftc -Xllvm -Xswiftc -sil-disable-pass=copy-to-borrow-optimization`).
In swift-io the trigger was removed instead: `IO.Event.Selector.Scope` dropped
its `Mutex<Token?>` field for a plain `var Shutdown.Token?` (swift-io commit
`6dad19ba`).

## Harness

`Tests/Reproducer Tests.swift` and `Sources/Reproducer/main.swift` stage both
modules in a temp directory, build them with `swiftc` OUT OF PROCESS (each
module needs its own flags), and run the client 5 times. Bug fired = any `BUG`
line. Absent = every run prints `PASS` with no `BUG` line. Anything else is
inconclusive and does not fail. It has only been seen on macOS, so
`withKnownIssue` uses `when:` macOS.

## Provenance

`swift-institute/Experiments` at commit `f1c4db4d390c12af5ec454dfb506feaa4ec5e841`:

- `copytoborrow-actor-state-mutex-miscompile/`: the 87-line reproducer, ported
  unchanged as `BugLib.swift.txt` and `BugTest.swift.txt`.
- `swift-copytoborrow-bug/`: the full-context original from swift-io (about 20
  files, depends on swift-kernel, swift-async, swift-ownership-primitives and
  swift-buffer-primitives by path). Kept in `evidence/` only.
- `actor-state-inline-fallback-repro/`: the negative control that ruled out the
  inline-executor and cross-thread theories. Kept in `evidence/` only.

Background: `swift-institute/Research` `swift-compiler-bug-catalog.md` §A6 at
commit `bb5f0a66530198802394dddd07bd93e351e6153b`.
