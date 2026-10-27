# Swift Issue: SILGen crash on a typed-throws closure cast inline to `@Sendable` into a generic `Sendable` parameter

**Upstream:** **NOT FILED.** This directory is the institute's record.

**Classification:** `swift-frontend` crash in SILGen (signal 5, exit status 133).
The source is valid Swift; the let-bound form below compiles and runs.

## Minimal reproducer

`reproducer.swift` (also staged as `Sources/Reproducer/Crash.swift.txt` for the
out-of-process harness):

```swift
struct CapturedSendable: Sendable {
    let payload: any Sendable
    init<V: Sendable>(_ value: V) { self.payload = value }
}

struct CapturedStore {
    var slots: [CapturedSendable] = []
    mutating func insert<V: Sendable>(_ value: V) -> Int {
        slots.append(CapturedSendable(value))
        return slots.count - 1
    }
}

enum TestError: Error, Sendable { case bad }

func triggerCrash() {
    var store = CapturedStore()
    let id = store.insert({ (x: Int) throws(TestError) in
        guard x >= 0 else { throw .bad }
        return x * 2
    } as @Sendable (Int) throws(TestError) -> Int)
    _ = id
}

triggerCrash()
```

```bash
xcrun swiftc -Onone -g -swift-version 6 -c reproducer.swift -o /dev/null
```

**Actual:** the frontend crashes, exit status 133. Innermost frames:

```
6.	While silgen closureexpr SIL function "@$s4null12triggerCrashyyFS2iYbAA9TestErrorOYKcfU_".
4  swift-frontend  createInputFunctionArgument(swift::Lowering::SILGenBuilder&, swift::SILType, ...)
5  swift-frontend  (anonymous namespace)::LoweredParamGenerator::claimNext()
6  swift-frontend  (anonymous namespace)::EmitBBArguments::handleValue(...)
9  swift-frontend  swift::Lowering::SILGenFunction::emitBasicProlog(...)
11 swift-frontend  swift::Lowering::SILGenFunction::emitClosure(swift::AbstractClosureExpr*)
```

SILGen runs out of lowered parameters while it builds the closure's prolog: it
lowers the closure's `Int` parameter against the `@Sendable` typed-throws type
the cast asks for.

**Expected:** compiles.

## Trigger characterization

| Ingredient | Removed / replaced by | Result |
|---|---|---|
| inline `as @Sendable (Int) throws(TestError) -> Int` cast | closure bound to a typed `let` first, then passed | compiles (`evidence/control-let-bound-closure.swift`) |
| typed throws `throws(TestError)` | untyped `throws` | compiles (`evidence/control-untyped-throws.swift`) |
| generic `<V: Sendable>` callee | non-generic overload taking `@Sendable (In) throws(E) -> Out` | compiles (original record) |
| the nine package settings (`ExistentialAny`, `NonisolatedNonsendingByDefault`, `Lifetimes`, strict memory safety, …) | none at all | still crashes |
| `-g` | not needed | still crashes |

The original package turned on five upcoming features, three experimental
features and strict memory safety. None of them is needed: the reproducer
crashes with no feature flags. The harness passes none.

This is not `swift-issue-irgen-nonthrowing-typed-throws-closure-crash`: that one
aborts in IRGen and needs no cast. The non-throwing sibling of this shape, at
`-O`, is `swift-issue-generic-specializer-sendable-closure-cast`.

## Toolchains

| `swiftc --version` | Result |
|---|---|
| Apple Swift version 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), macOS arm64 | crashes (original record, 2026-04-21 and 2026-04-30) |
| Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1), macOS arm64 | crashes, with and without the original settings (`evidence/macos-6.4.2-run.txt`, 2026-10-27) |

Linux and Windows were not run locally; CI covers them.

## Workaround

Bind the closure to a `let` with the full function type, then pass the `let`:

```swift
let closure: @Sendable (Int) throws(TestError) -> Int = { (x: Int) throws(TestError) in
    guard x >= 0 else { throw .bad }
    return x * 2
}
let id = store.insert(closure)
```

Or add a non-generic overload of the callee that takes the function type
directly. swift-machine-primitives used that form in its tests.

## Harness

`Tests/Reproducer Tests.swift` and `Sources/Reproducer/main.swift` run
`swiftc -Onone -g -swift-version 6 -c` on `Crash.swift.txt` in a child process,
because the source crashes the compiler. A non-zero exit with
`While silgen closureexpr` in the stack dump means the bug fired; exit 0 means
it is absent; anything else is inconclusive. SILGen does not depend on the
target, so `withKnownIssue` uses `when: { true }`. The test flips red once a
toolchain compiles the source.

## Provenance

Ported 2026-10-27 from `swift-institute/Experiments`
`silgen-sendable-typed-throws-closure-cast/` at commit
`f1c4db4d390c12af5ec454dfb506feaa4ec5e841` (created 2026-04-21). It surfaced when
swift-machine-primitives' tests stopped compiling on Swift 6.3.1. The reproducer
here is that file's code without its header comment. The original files are in
`evidence/original/`.
