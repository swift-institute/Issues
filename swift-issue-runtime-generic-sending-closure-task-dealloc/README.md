# Swift Issue: "freed pointer was not the last allocation" passing a `sending` closure through a generic `@Sendable` async function value

**Upstream:** **NOT FILED.** This directory is the institute's record. A search
of swiftlang/swift for this abort message with `sending` found no match
(2026-10-27). Related reports with the same message but different shapes
include swiftlang/swift#88794 and #92017.

**Classification:** runtime abort from compiler-generated code, at `-Onone`. The
program compiles cleanly. When it runs, `swift_task_dealloc` finds the task
allocator's stack order broken and aborts (SIGABRT, exit status 134). `-O` hides
it.

## The code is valid

The program contains no `unsafe` code, no pointers, no `@unchecked Sendable` and
no `nonisolated(unsafe)`. It builds with no warnings under Swift 6 strict
concurrency with `-strict-memory-safety -warnings-as-errors`. The closure is
called once, and nothing escapes it. User code never touches the task allocator:
async frames are allocated and freed only by code the compiler generates. So a
broken allocation order is a compiler or runtime defect, not undefined behaviour
in the source.

## Minimal reproducer

`reproducer.swift` (also staged as `Sources/Reproducer/Crash.swift.txt` for the
out-of-process harness):

```swift
struct One<Value: Sendable>: Sendable {
    let body: @Sendable (sending () -> Value) async -> Void

    func resume(returning value: sending Value) async {
        await body { value }
    }
}

@main
struct App {
    static func main() async {
        let one = One<String> { @Sendable (thunk: sending () -> String) async in
            print(thunk())
        }
        await one.resume(returning: "hello")
    }
}
```

```bash
xcrun swiftc -Onone -swift-version 6 -parse-as-library reproducer.swift -o repro && ./repro
```

**Actual:** prints `hello`, then `freed pointer was not the last allocation`,
SIGABRT, exit status 134. Innermost frames (lldb):

```
frame #5: libswift_Concurrency.dylib`swift::_swift_task_dealloc_specific(swift::AsyncTask*, void*) (.cold.2) + 84
frame #6: libswift_Concurrency.dylib`swift_task_dealloc + 124
frame #7: rg`static App.main() at reproducer.swift:15:19
```

Line 15 is `await one.resume(returning: "hello")`.

**Expected:** prints `hello` and exits 0, as it does at `-O`.

## Trigger characterization

Each ingredient was removed in turn (`evidence/macos-6.4.2-run.txt`).

| Ingredient | Removed / replaced by | Result at `-Onone` |
|---|---|---|
| `sending` on the closure parameter `(sending () -> Value)` | `(() -> Value)` | runs clean (`evidence/control-no-sending.swift`) |
| `sending` on `resume`'s own parameter | plain `value: Value` | runs clean (`evidence/control-plain-resume-param.swift`) |
| generic `One<Value>` | non-generic, `Value = String` | runs clean (`evidence/control-non-generic.swift`) |
| `async` on the function value | synchronous | runs clean (`evidence/control-synchronous.swift`) |
| `-Onone` | `-O` | runs clean |
| `~Copyable` payload, `Optional.take()` capture, typed throws, `sending` result | none of them (the reproducer has none) | still aborts; `evidence/variant-noncopyable-typed-throws.swift` has all of them and also aborts |
| explicit `@Sendable (thunk: …) async in` annotation | inferred closure `{ thunk in … }` | still aborts (`evidence/variant-inferred-closure.swift`) |
| `Value` is `String` | `Int` | still aborts (`evidence/variant-int-value.swift`) |

The generic parameter is what forces a reabstraction thunk for the closure, so
the likely fault is in how that thunk, or its caller, orders the async frame
allocations around a `sending` argument. That is a hypothesis, not checked in SIL.

`~Copyable` is not needed, although the experiment it came from used it:
`evidence/variant-copyable-payload.swift`, the original program with a copyable
payload, still aborts.

## History: the SILGen crash no longer fires

The experiment `silgen-thunk-noncopyable-sending-capture` recorded a SILGen
crash on Swift 6.3.1 (signal 11, "While emitting reabstraction thunk", in
`buildThunkBody` / `createThunk`). It mentioned this runtime abort only as a
symptom of "in-package adjacent variants", not checked in.

On Apple Swift 6.4.2 the SILGen crash is gone: the original file compiles with
its nine package settings and with none, and `swift build` of the original
package succeeds. The program it builds now aborts with this message at
`-Onone` (exit status 134) and prints `OK` at `-O`. The full original file is in
`evidence/original/`.

## Toolchains

| `swiftc --version` | Result |
|---|---|
| Apple Swift version 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), macOS arm64 | original file crashes SILGen (original record); the runtime abort is described for adjacent variants only |
| Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1), macOS arm64 | compiles; reproducer and original file abort at `-Onone`, run clean at `-O` (2026-10-27) |

Linux and Windows were not run locally; CI covers them.

## Workaround

Drop `sending` from either the closure's parameter or the outer function's
parameter, if the types allow it. Or keep the value in two callbacks instead of a
thunk, as `Effect.Continuation.One` in swift-effect-primitives does (`_onValue`
plus `_onError`). Building with `-O` also avoids it for code we compile.

## Harness

`Tests/Reproducer Tests.swift` and `Sources/Reproducer/main.swift` compile
`Crash.swift.txt` with `swiftc -Onone -parse-as-library` in a child process and
run the result as a second child process with `SWIFT_BACKTRACE=enable=no`, so
the abort cannot take down the test runner. A child that dies on a signal with
"not the last allocation" on stderr means the bug fired. A child that prints
`hello` and exits 0 means it is absent. Anything else is inconclusive.

The allocations are made by compiler-generated code, not by the target, so
`withKnownIssue` uses `when: { true }`. The test flips red once a toolchain runs
the program to completion.

## Provenance

Ported 2026-10-27 from `swift-institute/Experiments`
`silgen-thunk-noncopyable-sending-capture/` at commit
`f1c4db4d390c12af5ec454dfb506feaa4ec5e841` (created 2026-04-17). It surfaced
during the `~Copyable & Sendable` widening of swift-effect-primitives'
`Effect.Continuation.One._resume`. The reproducer here is a fresh reduction of
that file on 6.4.2. The original files are in `evidence/original/`.
