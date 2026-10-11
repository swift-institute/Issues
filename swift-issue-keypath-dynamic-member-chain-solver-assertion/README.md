# Constraint-solver assertion: key-path application on a value whose dynamic-member key path is rooted in another dynamic-member type

Canonical work item: [swift-institute/Issues#61](https://github.com/swift-institute/Issues/issues/61). Upstream: [swiftlang/swift#87174](https://github.com/swiftlang/swift/issues/87174) (open), which has the same assertion and the same chained `@dynamicMemberLookup` shape. Nothing new to file.

## Reproducer

[`Reduced.swift.txt`](Reduced.swift.txt), 13 lines, standard library only:

```swift
@dynamicMemberLookup
struct C {
    subscript<M>(dynamicMember keyPath: KeyPath<C, M>) -> M { fatalError() }
}

@dynamicMemberLookup
struct S {
    subscript<M>(dynamicMember keyPath: KeyPath<C, M>) -> M { fatalError() }
}

func f<R>(_ s: S, _ keyPath: KeyPath<S, R>) -> R {
    s[keyPath: keyPath]
}
```

`swiftc -typecheck Reduced.swift` on an assertions-enabled compiler fails with:

```
Assertion failed: ((path.size() == 1 && path[0].getKind() == ConstraintLocator::SubscriptMember) || (path.size() == 2 && path[1].getKind() == ConstraintLocator::KeyPathDynamicMember)), function addKeyPathApplicationRootConstraint, file CSSimplify.cpp, line 16247.
```

| Toolchain | Result |
|---|---|
| swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a (assertions) | assertion, signal 6 |
| swift-DEVELOPMENT-SNAPSHOT-2026-07-11-a (6.5-dev, assertions) | assertion, signal 6 |
| Apple Swift 6.4 (swiftlang-6.4.0.34.1, Xcode) | exit 0, but this compiler has no Sema assertions (the assertion text is absent from its `swift-frontend`), so this is unchecked rather than correct |

## Mechanism

`s[keyPath:]` is tried both as a real key-path application and, because `S` is `@dynamicMemberLookup`, as a dynamic member. That dynamic member goes through `S`'s subscript into `C`, and `C` is `@dynamicMemberLookup` too. Taking `C`'s dynamic member gives a three-element locator path (subscript member, key-path dynamic member, key-path dynamic member). The assertion allows at most two. It needs two distinct `@dynamicMemberLookup` types, with the outer one's key-path subscript rooted at the inner one.

## Where it came from

In swift-molecules/swift-structured-queries, `extension TableDraft`'s `static subscript(dynamicMember: KeyPath<PrimaryTable.Type, some Statement<PrimaryTable>>)` applied `PrimaryTable.self[keyPath: keyPath]`. `Table` has a static dynamic-member subscript rooted at `TableColumns`, and `TableDefinition` is itself `@dynamicMemberLookup`. The package now routes the application through a generic helper, `project(_:through:)` in `PrimaryKeyedProtocols.swift`, which hides the bug. Restoring the direct expression (verified 2026-10-11 on the 6.4 snapshot, with a probe confirming the body was type-checked) brings the assertion back. Keep the helper until #87174 is fixed.
