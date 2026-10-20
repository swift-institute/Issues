# Windows assertions compiler: SILGen abort on a non-throwing closure converted to nested typed throws

Observed 2026-10-20 in swift-molecules/swift-memory-allocation, commit `21a907ea`, CI run 39416803412, job "Build · Windows · release". The build enables every package trait, which brings in swift-atoms/swift-growth. The same commit built green on the same leg without the traits (run of 07:31 UTC).

## Trigger site

`swift-growth/Sources/Growth/Growth.Policy.swift:67`, in `extension Growth.Policy where Element: ~Copyable`:

```swift
@inlinable
public static var exact: Self {
    Self { $0 }
}
```

The initializer takes a function of type `(Count) throws(Error) -> Count`, where `Error` is nested in the generic `Growth.Policy`. The closure `{ $0 }` is non-throwing. This is the shape of this entry: a non-throwing closure converted to a typed-throws function whose error type is nested in a generic container, here inside an extension constrained with `~Copyable`.

## Failure

```text
Assertion failed: !getErrorResult().getInterfaceType()->hasArchetype() && "interface type of result should not contain context archetypes", file ...\swift\lib\AST\ASTContext.cpp, line 5537
While evaluating request ASTLoweringRequest(Lowering AST to SIL for module Growth)
While silgen visitDecl extension of Growth.Policy (at ...\Growth.Policy.swift:39:1)
While silgen emitFunction SIL function "@$s6GrowthAAO6PolicyVAARi_zrlE5exactADy_xGvgZ".
 for getter for exact (at ...\Growth.Policy.swift:67:23)
Exception Code: 0xC000001D
```

Toolchain: Swift 6.4.1 (swift-6.4.1-RELEASE) Windows with assertions. Exit: `error: emit-module command failed due to exception 29`.

## Relation to this entry

Same source shape as the entries above, but a different assertion in a different phase: here SILGen asserts that the error-result interface type contains no context archetypes, where the retained captures abort in IRGen on `hasErrorResult()`. Whether swiftlang/swift#90789 also removes this assertion has not been verified. It is not in Swift 6.4.1.

No workaround is applied in swift-growth and no platform leg is excluded; the Windows leg stays red until a toolchain with the fix is used.

## Impact

Any package whose trait-enabled graph includes swift-growth fails its Windows leg (first seen: swift-memory-allocation).
