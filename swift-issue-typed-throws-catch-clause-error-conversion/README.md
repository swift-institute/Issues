# `swift-issue-typed-throws-catch-clause-error-conversion`

Throwing the **enclosing function's** typed error from inside a `catch`
clause whose `do` block throws a **different** concrete error type crashes
SILGen. The `throw` is emitted against the do block's thrown type instead of
the function's, and SILGen then tries to erase a non-class concrete type into
an existential error box.

## Minimal reproduction

One file, one bare `swiftc` invocation, no dependencies
(`Sources/Reproducer/Crash.swift.txt`):

```swift
enum Inner: Error { case a }
enum Outer: Error { case x }

func make() throws(Inner) { throw .a }

func g() throws(Outer) {
    do {
        try make()
    } catch let error as Inner {
        _ = error
        throw Outer.x           // crash site
    }
}
```

```sh
swiftc -swift-version 6 -parse-as-library -c Crash.swift -o Crash.o
```

Load-bearing (each verified by removal-then-rebuild on 6.3.3-RELEASE, macOS
arm64, 2026-07-30):

- the enclosing function's **typed** `throws(Outer)`. An untyped `throws` is
  clean.
- a **concrete-type catch pattern** — `catch let error as Inner` or
  `catch is Inner`. A bare `catch` is clean. The pattern must be exhaustive
  for the do block's thrown type: `catch Inner.a` is not, and is correctly
  diagnosed (`thrown expression type 'Inner' cannot be converted to error
  type 'Outer'`) rather than crashing.

How the thrown value is produced does not matter: routing it through a
conversion function (`throw convert(error)`) aborts identically. It is the
`throw` being lexically inside the concrete-typed catch clause that triggers
it.

**Not** required: an initializer — a plain `func` crashes identically,
although the Institute's production instance is an `init`, which is why the
production stack frame is `emitValueConstructor`. Also not required:
optimization (`-Onone` and `-O` behave identically), whole-module,
`-enable-default-cmo`, a `switch` in the catch body, more than one module, or
more than one file.

## Affected Swift versions

Each row confirmed 2026-07-30 on the shipped resource, macOS arm64,
`swift --version`-checked.

| Toolchain | Result |
|---|---|
| 6.3.3-RELEASE (swiftly) | **signal 11** — bad pointer dereference in `SILGenFunction::emitExistentialErasure`, reached from `emitThrow` inside `emitCatchDispatch` |
| Apple Swift 6.4 (Xcode, swiftlang-6.4.0.27.1) | **abort** — `Assertion failed: (FormalConcreteType->isBridgeableObjectType())`, `createInitExistentialRef`, `SILBuilder.h:2244` |
| 6.4.x-snapshot-2026-07-23 (+assertions) | **abort** — `Assertion failed: (destErrorType == SILType::getExceptionType(getASTContext()))`, `emitThrow`, `SILGenStmt.cpp:1758` |
| main-snapshot-2026-07-11 (6.5-dev) | **rejected** — `error: INTERNAL ERROR: feature not implemented: throw conversion from 'Inner' to 'Outer'` |

**Not fixed on any tested toolchain, including 6.5-dev `main`.** The
progression is diagnosis, not repair: the 6.4 assertion names the malformed
existential erasure, the 6.4.x assertion names the wrong destination error
type outright, and 6.5-dev converts the crash into a hard "feature not
implemented" diagnostic. The program remains uncompilable on all four.

On 6.3.3 the failure is a bad pointer dereference in a NoAsserts build, so it
is undefined behaviour: locally it aborted on 11 of 12 attempts. Every
assertions-enabled toolchain and Apple Swift 6.4 abort deterministically, and
the CI container reproduced it deterministically. Both harnesses therefore
retry three times before reporting a fix.

## Harness

Repository two-target convention with the single-file out-of-process shape:
`…-Tests` wraps the probe in `withKnownIssue` with `when: { true }` (green
while the bug fires; **red the moment `Crash.swift.txt` compiles cleanly** —
the fix-detection signal); `…-Repro` is the same probe standalone (exit 1 =
fires, 0 = fixed, 2 = inconclusive). The 6.5-dev diagnostic counts as firing:
the program is not compilable either way.

## Upstream

**Destination**: `swiftlang/swift`. The 6.5-dev wording
(`feature not implemented: throw conversion from 'Inner' to 'Outer'`) suggests
the case is known to the typed-throws implementation as unimplemented rather
than unrecognised, so a duplicate check on that phrasing belongs in any filing.
**Filing remains principal-gated** and none has been made from this record.

## Workaround

Any `throw` lexically inside the concrete-typed catch clause crashes,
however the thrown value is produced — routing it through a conversion
function (`throw convert(error)`) still aborts. Two forms were verified
clean on 6.3.3 (three attempts each) and Apple Swift 6.4:

```swift
// 1 — bare `catch`, which loses the bound concrete error
func g() throws(Outer) {
    do { try make() } catch { throw Outer.x }
}

// 2 — move the throw out of the catch clause entirely
func g() throws(Outer) {
    let outcome = Result { () throws(Inner) in try make() }
    switch outcome {
    case .success: return
    case .failure: throw Outer.x
    }
}
```

Making the enclosing function's `throws` untyped also avoids it. Attribute
suppressions do not help — the failure is in SILGen, not optimization.

## Provenance (Institute discovery context)

Surfaced by `swift-standards/swift-sockets-standard`, gating leg
`Ubuntu (Swift 6.3, release)`, tracked on
[swift-standards/swift-sockets-standard#2](https://github.com/swift-standards/swift-sockets-standard/issues/2).
The abort is not in that package's own sources: it is in the
`swift-ietf/swift-rfc-9293` dependency (`main` at `823e7e4`), target
`RFC 9293 3 Functional Specification`, while lowering
`RFC_9293.3.1.Header.init(bytes:)`
(`Sources/RFC 9293 3 Functional Specification/RFC_9293.3.1.Header.swift:182`):

```swift
public init<Bytes: Collection>(bytes: Bytes) throws(Error)
where Bytes.Element == Byte {
    ...
    do {
        dataOffset = try RFC_9293.`3`.`1`.DataOffset(rawValue: offsetValue)
    } catch let error as RFC_9293.`3`.`1`.DataOffset.Error {
        switch error {
        case .valueTooSmall: throw Error.dataOffsetTooSmall
        case .valueTooLarge: throw Error.dataOffsetTooLarge
        case .notAligned: throw Error.dataOffsetTooSmall
        }
    }
    ...
}
```

`init(bytes:)` is `throws(Header.Error)`; the `do` block throws
`DataOffset.Error`; the catch clause matches that concrete type and rethrows
`Header.Error` — exactly the shape above. `-O`, `-enable-default-cmo`,
`-enable-testing` and the generic `Collection` constraint all appear in the
failing invocation and none of them are part of the trigger.
