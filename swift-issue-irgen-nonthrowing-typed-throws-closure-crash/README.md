# IRGen asserts when converting a non-throwing closure to nested generic typed throws

Local tracking: [swift-institute/Issues#9](https://github.com/swift-institute/Issues/issues/9)

Upstream: [swiftlang/swift#87030](https://github.com/swiftlang/swift/issues/87030), fixed on `main` by [swiftlang/swift#90789](https://github.com/swiftlang/swift/pull/90789).

## Observed behavior

On an assertions-enabled Swift compiler, emitting debug IR for a non-throwing closure converted to a typed-throws function can abort with signal 6:

```text
SILFunctionType::getMutableErrorResult(): Assertion `hasErrorResult()' failed.
While evaluating request IRGenRequest
```

The closure's lowered SIL function is non-throwing, but SILGen used to emit a synthetic `$error` `debug_value` from the abstract throwing type. IRGen then attempted to read an error-result slot that the lowered function did not have.

## Expected behavior

Converting a non-throwing closure to a compatible typed-throws function value is valid. The compiler should emit IR without adding debug information for a nonexistent error-result slot.

## Minimal reproduction

The standalone harness compiles two neutral source variants:

- `ConstrainedExtension.swift.txt` assigns `{ $0 }` in a constrained extension of a generic container.
- `DirectInitialization.swift.txt` passes `{ _ in false }` directly to a generic container initializer.

Both variants have the same core shape:

```swift
struct Container<Value> {
    var transform: (Value) throws(Failure) -> Value
    enum Failure: Error { case invalid }
}
```

The stored function uses an error nested in the generic container, and the assigned closure is non-throwing. The harness invokes:

```console
swiftc -g -Onone -swift-version 6 -c Reproducer.swift
```

The two variants are kept separate so a future change cannot accidentally preserve only one conversion context.

## Trigger and controls

The reproduced failure requires:

1. a non-throwing closure converted to a typed-throws function;
2. an error type nested in a generic container;
3. debug information emission; and
4. an assertions-enabled affected compiler.

Verified controls in the retained upstream evidence include hoisting the error type, using an untyped `throws`, removing the generic container, or making the stored closure non-throwing. Each removes the failing shape.

## Affected versions and configuration

- Reproduced on Swift.org Swift 6.2.3 and 6.3 development assertions builds.
- Reproduced on arm64 macOS and arm64 Linux assertions toolchains; the original discovery also occurred on a Windows assertions CI leg.
- No-assertions Swift 6.2.3 and 6.3 toolchains compile the source, so their clean result is only a negative control for the assertion, not proof that the invalid debug information was absent.
- The upstream fix merged to `main` on 2026-07-22. The CI harness treats pre-6.5 assertions toolchains as known-affected and Swift 6.5-or-newer toolchains as regression coverage.

## Workaround

Give the closure an explicit typed-throws signature, which avoids the non-throwing-to-throwing conversion:

```swift
{ (value: Bool) throws(Container<Bool>.Failure) -> Bool in value }
```

Hoisting the error type out of the generic container also avoids the failure, but changes the public type shape.

## Upstream status

This is the same defect as [swiftlang/swift#87030](https://github.com/swiftlang/swift/issues/87030), not a new upstream issue. The direct-initialization variant has the same `hasErrorResult()` assertion, IRGen phase, debug configuration, and non-throwing-to-typed-throws conversion described by the upstream fix.

[swiftlang/swift#90789](https://github.com/swiftlang/swift/pull/90789) fixed the source invariant by emitting the synthetic `$error` debug value only when the lowered SIL function has an error result, and added verifier coverage. It merged on 2026-07-22.

## Supplemental provenance and impact

The defect was independently found in a test fixture whose domain-specific names were not part of the trigger. That fixture's characterization and compiler logs remain under `evidence/direct-initialization/`. The earlier constrained-extension source and its public-source provenance remain under `evidence/constrained-extension/`.

The original workaround changed only the affected test fixture. No domain package, product, or architecture concept is required to understand or run this reproducer.
