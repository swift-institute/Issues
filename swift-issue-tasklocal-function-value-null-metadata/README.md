# `swift-issue-tasklocal-function-value-null-metadata`

A `@TaskLocal` whose **value type is a function type** produces a
null type-metadata argument to `swift_task_localValuePush` under `-O` on
Swift 6.3.3. The runtime then reads the value-witness-table slot at
`metadata - 8` and faults:

```
*** Program crashed: Bad pointer dereference at 0xfffffffffffffff8 ***
  0  swift_task_localValuePush + … in libswift_Concurrency.so
  1 [inlined] specialized TaskLocal.withValue<A>(_:operation:file:line:)
```

`0xfffffffffffffff8` is `0 - 8`: the value witness table pointer sits one
word *before* the type metadata pointer, so the address is the direct
consequence of a **null metadata pointer**, not of a corrupted task or a
missing current task.

## Minimal reproduction

Two statements, one bare `swiftc` invocation, no dependencies, no
concurrency, no test framework (`Sources/Reproducer/Crash.swift.txt`):

```swift
@TaskLocal var handler: (@Sendable () -> Void)?

$handler.withValue({}, operation: {})
print("ok")
```

```sh
swiftc -O -swift-version 6 main.swift -o probe && ./probe   # signal 11 on 6.3.3
```

Load-bearing (each verified by substitution-then-rerun on 6.3.3-RELEASE,
macOS arm64 and `swift:6.3-noble` on Linux arm64 + x86_64, 2026-07-30):

- **`-O`.** `-Onone` is clean on every shape and every toolchain tested.
- **A function-typed value.** `(@Sendable () -> Void)?`,
  `(@Sendable (String) -> Void)?` and the non-optional
  `@Sendable (String) -> Void` all crash. `Int?` and `String?` are clean.
  Optionality is *not* part of the trigger; the function type is.

**Not** required: `async`, a surrounding `Task`, a current task at all
(the reproducer above runs on the main thread with no task), the
`operation:` body reading the task local, a test framework, more than one
module, whole-module, or `-enable-default-cmo`. Declaration form does not
matter either: a global `@TaskLocal`, a `static` one in an enum, and a
`static` one in an extension of an enum in a *different* module all crash
identically.

## The malformed metadata request

The defect is visible directly in the emitted IR. Both toolchains emit the
same call shape; only the mangled name differs.

| Toolchain | metadata request emitted for the task local's value type |
|---|---|
| 6.3.3-RELEASE | `` @"$sxRi_zRi0_zlyytIseghr_SgMD" `` |
| 6.4-dev snapshot | `` @"$syyYbcSgMD" `` |

`$syyYbcSgMD` demangles to `Optional<@Sendable () -> ()>` — a **formal**
function type, which the runtime can instantiate.

`$sxRi_zRi0_zlyytIseghr_SgMD` demangles to an `Optional` of an
`ImplFunctionType` carrying `ImplPatternSubstitutions` over a
`DependentGenericSignature` — a **lowered SIL** function type that still
contains generic parameters. It is handed to
`__swift_instantiateConcreteTypeFromMangledName`, the entry point for
mangled names with *no* generic parameters left to substitute. Resolution
fails, the call returns null, and `swift_task_localValuePush` dereferences
`null - 8` reaching for the value witness table.

So the specializer emits a *dependent* mangled name through the *concrete*
instantiation path. The value type being a function type is what makes the
lowered form differ from the formal one; for `Int?` or `String?` the two
coincide and nothing is malformed.

## Affected Swift versions

Each row confirmed 2026-07-30 against the minimal reproducer above,
`swift --version`-checked.

| Toolchain | Platform | `-O` | `-Onone` |
|---|---|---|---|
| 6.3.3-RELEASE | macOS arm64 | **signal 11** | clean |
| 6.3.3-RELEASE (`swift:6.3-noble`) | Linux arm64 | **signal 11** | clean |
| 6.3.3-RELEASE (`swift:6.3-noble`) | Linux x86_64 | **signal 11** | clean |
| Apple Swift 6.4 (`swiftlang-6.4.0.27.1`) | macOS arm64 | clean | clean |
| 6.4.x-snapshot-2026-07-23 (+assertions) | macOS arm64 | clean | clean |
| main-snapshot-2026-07-11 (6.5-dev) | macOS arm64 | clean | clean |
| `swiftlang/swift:nightly-main-noble` (6.5-dev) | Linux arm64 | clean | clean |

**Fixed on every 6.4 and later toolchain tested; broken on 6.3.3 on every
platform tested.** This is not a Linux-specific defect — it surfaced on a
Linux CI leg only because that leg is the one pinned to 6.3.

Deterministic: 5 consecutive runs aborted on 6.3.3 macOS arm64, and every
Linux invocation aborted. The harnesses still retry three times, so that a
single anomalous clean run cannot announce a fix that has not landed.

## Harness

Repository two-target convention with the single-file out-of-process shape.
The bug crashes the *produced binary*, not the compiler, but an in-process
trigger would still take the whole test runner down with SIGSEGV, so the
trigger ships as `Crash.swift.txt` and is compiled **and run** out of
process.

- `…-Tests` — Swift Testing. `withKnownIssue` is active
  (`when: { true }`) when the test target itself was built by a compiler
  **older than 6.4**, and inactive at 6.4 or newer. On 6.3.x the leg is
  green while the bug fires and flips **red** if it stops — the
  backport-detection signal. On 6.4+ the expectation runs unguarded, so the
  leg is green because the bug is fixed and flips **red** on a regression.
  Both directions are live signals.
- `…-Repro` — the same probe standalone: exit 1 = fires, 0 = fixed,
  2 = inconclusive.

Both harnesses invoke `swiftc` from `PATH` and assume it is the same
toolchain that built them, which holds under `swift test` and in CI.

## Upstream

**Destination**: `swiftlang/swift`. Already fixed on 6.4 and later, so any
filing is a **backport request against the 6.3 release branch**, not a new
defect report; a duplicate check should search the metadata-mangling path
(`__swift_instantiateConcreteTypeFromMangledName`,
`ImplPatternSubstitutions`) rather than `TaskLocal`, since the task-local
API is only the caller that happens to demand the metadata.
**Filing remains principal-gated** and none has been made from this record.

## Workaround

Wrap the function value in a nominal type. Both forms verified clean on
6.3.3 `-O` (macOS arm64):

```swift
// 1 — struct wrapper
struct Handler: Sendable {
    let run: @Sendable () -> Void
}
@TaskLocal var handler: Handler?

// 2 — final class wrapper
final class Handler: Sendable {
    let run: @Sendable () -> Void
    init(run: @escaping @Sendable () -> Void) { self.run = run }
}
@TaskLocal var handler: Handler?
```

A `typealias` does **not** help — `typealias Handler = @Sendable () -> Void`
crashes identically, because the structural type is unchanged. Building the
consumer at `-Onone` also avoids it, and is not a shippable answer for a
release configuration.

## Provenance (Institute discovery context)

Surfaced by `swift-primitives/swift-structured-queries-primitives`, gating
leg `Ubuntu (Swift 6.3, release)`, on
[run 30440815682](https://github.com/swift-primitives/swift-structured-queries-primitives/actions/runs/30440815682),
tracked on
[swift-primitives/swift-structured-queries-primitives#2](https://github.com/swift-primitives/swift-structured-queries-primitives/issues/2).

The crash was reported inside
`ReportTests."Invalid update filter reports through the bound handler instead of trapping"`
(`Tests/Structured Queries Primitives Tests/RegressionTests.swift:140`), whose
body calls `QueryFragment.Report.$invalid.withValue(_:operation:)`. The task
local it binds is declared in the product target:

```swift
extension QueryFragment.Report {
    @TaskLocal public static var invalid: (@Sendable (String) -> Void)?
}
```

A `(@Sendable (String) -> Void)?` task local — exactly the trigger. Neither
`swift-testing` nor the `Report` namespace nor the cross-module boundary is
load-bearing; the reduction above drops all three and still crashes. The
origin diagnosis had already ruled out an `InlineSnapshotTesting`-owned
crash class (that package is not a dependency, and no snapshot frames appear
in the backtrace), which this reduction confirms from the other direction:
the trigger needs no test framework at all.
