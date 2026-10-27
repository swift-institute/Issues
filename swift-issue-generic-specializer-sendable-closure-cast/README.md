# Swift Issue: GenericSpecializer assertion on a closure cast inline to `@Sendable` into a generic `Sendable` parameter

**Upstream:** **NOT FILED.** This directory is the institute's record.

**Classification:** `swift-frontend` abort (signal 6) in the `GenericSpecializer`
SIL pass at `-O`, on an assertions-enabled compiler. The source is valid Swift.

**Not run locally.** The assertion was recorded only on a Linux 6.4-dev
assertions toolchain. The only toolchain here is Apple Swift 6.4.2 on macOS
arm64, a release build without assertions, and it builds the source cleanly.
That is not evidence of a fix. CI on the Linux nightly images (which have
assertions) is this entry's evidence.

## Minimal reproducer

`reproducer.swift` (also staged as `Sources/Reproducer/Crash.swift.txt` for the
out-of-process harness):

```swift
struct CapturedSendable: Sendable {
    let payload: any Sendable
    init<V: Sendable>(_ value: V) { self.payload = value }
}

struct CapturedID<Value: Sendable>: Sendable {
    let index: Int
}

struct CapturedStore {
    var slots: [CapturedSendable] = []
    mutating func insert<Value: Sendable>(_ value: Value) -> CapturedID<Value> {
        slots.append(CapturedSendable(value))
        return CapturedID(index: slots.count - 1)
    }
}

func triggerCrash() {
    var store = CapturedStore()
    let id = store.insert({ (x: Int) in x * 2 } as @Sendable (Int) -> Int)
    _ = id
}

triggerCrash()
```

```bash
swiftc -O -wmo -swift-version 6 \
  -strict-memory-safety \
  -enable-upcoming-feature ExistentialAny \
  -enable-upcoming-feature InternalImportsByDefault \
  -enable-upcoming-feature MemberImportVisibility \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-experimental-feature LifetimeDependence \
  -enable-experimental-feature Lifetimes \
  -enable-experimental-feature SuppressedAssociatedTypes \
  -enable-upcoming-feature InferIsolatedConformances \
  -c reproducer.swift -o /dev/null
```

The flags are the settings of the package the crash was recorded in. Which of
them it needs is not known: trimming them needs an affected toolchain.

**Actual (Linux 6.4-dev, assertions):**

```
swift-frontend: .../swift/SIL/TypeSubstCloner.h:121:
TypeSubstCloner<GenericCloner>::ApplySiteCloningHelper::ApplySiteCloningHelper(...):
Assertion `Subs.empty() || SubstCalleeSILType == Callee->getType().substGenericArgs(...)' failed.
```

GenericSpecializer clones `CapturedStore.insert<Value: Sendable>` for the closure
type, and the substituted callee type does not match.

**Expected:** compiles.

## Trigger characterization

From the original record (not re-checked here):

| Ingredient | Removed / replaced by | Result |
|---|---|---|
| inline `as @Sendable (Int) -> Int` cast | closure bound to a typed `let` first, then passed | compiles (`evidence/control-let-bound-closure.swift`) |
| generic `<Value: Sendable>` callee returning `CapturedID<Value>` | non-generic overload taking `@Sendable (In) -> Out` | compiles |
| `-O` | `-Onone` | compiles: GenericSpecializer does not run |
| typed throws | not needed | — |

The `-Onone`, typed-throws sibling of this shape crashes SILGen instead:
`swift-issue-silgen-sendable-typed-throws-closure-cast`.

## Toolchains

| `swiftc --version` | Result |
|---|---|
| Swift version 6.4-dev (LLVM 885b338ea38aee1, Swift db4e13695491982), Ubuntu 24.04.4 x86_64, assertions | assertion fails (original record: swift-machine-primitives' Ubuntu 6.4 release CI leg, five call sites) |
| Apple Swift 6.4 (swiftlang-6.4.0.27.1), macOS arm64, no assertions | compiles (original record) |
| Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1), macOS arm64, no assertions | compiles at `-O` and `-Onone`, with and without the settings (`evidence/macos-6.4.2-run.txt`, 2026-10-27) |

The original record notes that the reduced file itself has no recorded crash
log: the assertion text comes from the production CI job. The first Linux CI
run of this entry is its first direct evidence.

## Workaround

Bind the closure to a `let` with the full function type before passing it, or
add a non-generic overload that takes the function type directly:

```swift
mutating func insert<In, Out>(_ value: @escaping @Sendable (In) -> Out) -> CapturedID<@Sendable (In) -> Out>
```

swift-primitives/swift-machine-primitives#6 used the overload.

## Harness

`Tests/Reproducer Tests.swift` and `Sources/Reproducer/main.swift` run
`swiftc -O -wmo` with the settings above on `Crash.swift.txt` in a child
process. A non-zero exit naming `TypeSubstCloner` or `SubstCalleeSILType` means
the bug fired. On a clean build they ask whether the compiler has assertions:
`swiftc -typecheck -Xfrontend -debug-assert-after-parse` crashes an assertions
build and exits 1 silently on a release build. A clean build on an assertions
compiler means the bug is absent; on a release compiler it is inconclusive, and
the test returns without a verdict.

`withKnownIssue` uses `when:` Linux, where the assertions nightlies run. The
test flips red once a Linux assertions toolchain builds the source. On macOS it
expects no crash, which is what the recorded macOS toolchains show.

Run locally on macOS arm64 6.4.2 only, which takes the inconclusive path.
The probe's "fired" and "absent" paths were checked with stub `swiftc` scripts
on `PATH`, not with a real affected compiler.

## Provenance

Ported 2026-10-27 from `swift-institute/Experiments`
`generic-specializer-sendable-closure-cast-release/` at commit
`f1c4db4d390c12af5ec454dfb506feaa4ec5e841` (created 2026-08-09). It surfaced
fixing swift-primitives/swift-machine-primitives#5; the fix landed in
swift-primitives/swift-machine-primitives#6. The reproducer here is that file's code without its
header comment. The original files are in `evidence/original/`.
