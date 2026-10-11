# `[Compiler][Rejects valid] associatedtype Element conformance leaks Copyable into a nested ~Copyable type`

Canonical work item: [swift-institute/Issues#12](https://github.com/swift-institute/Issues/issues/12)

Canonical evidence path: [swift-issue-noncopyable-sequence-conformance](https://github.com/swift-institute/Issues/tree/main/swift-issue-noncopyable-sequence-conformance)

This directory is runnable evidence for the canonical GitHub Issue.

A conditional conformance to a protocol declaring `associatedtype Element` causes the constraint checker to confuse that name with the outer `~Copyable` generic parameter. Correct behavior leaves the nested type’s `Heap<Element>` stored property valid; the source reports an erroneous "`Element` does not conform to `Copyable`" diagnostic.

Reproduce with the workspace build coordinator against this package’s `build` action. The retained source’s original command was `swift build`. No fresh result is included here.

Source-reported environment: Apple Swift 6.2.4, arm64 macOS 26. Structural workarounds are to use a top-level type or avoid a protocol whose associated type is named `Element`.

Upstream: [swiftlang/swift#87448](https://github.com/swiftlang/swift/issues/87448). Privacy screen: `PUBLIC_SAFE`.

## Swift 6.4 re-test and single-file reduction (2026-10-11)

This still reproduces on Apple Swift 6.4 (swiftlang-6.4.0.34.1), on 6.4-dev (snapshot 2026-07-23) and on 6.5-dev (main snapshot 2026-07-11). Neither a second module nor `-emit-module` is needed. [`Reduced.swift.txt`](Reduced.swift.txt) is one 17-line file. `swiftc -swift-version 6 -parse-as-library -c Reduced.swift` reports "type 'Element' does not conform to protocol 'Copyable'" at the `~Copyable` stored property.

Every one of these is required:
- The nested `~Copyable` type is `public`, inside a `public` outer type. With everything internal, it compiles.
- The conditional conformance to a protocol whose associated type is named `Element` comes before the nested type's declaration, in source order or file order. Moving it after the declaration compiles. This is why the package fails: SwiftPM orders `Buffer.Ring+Sequence.swift` before `Buffer.Ring.swift`.
- The associated type is named `Element`. Renaming it to `Value` compiles.

`-typecheck` alone is clean. The error appears once declarations are checked for code generation or module emission.

**Relation to upstream.** swiftlang/swift#87448 is the case where an extension without `where T: ~Copyable` declares the nested type. A maintainer explained that one as intended under SE-0427. This record is different: the extension does write `where Element: ~Copyable`, and the result depends on declaration order and access level. Coen's January comment on #87448 described this trigger, but the "intended" explanation does not cover it. A report was drafted in [UPSTREAM-DRAFT.md](UPSTREAM-DRAFT.md). Per Coen's 2026-10-11 ruling it is not filed upstream; this record is the report.

Workaround: declare the conformance after the type (put it in a file that sorts later), or give the protocol's associated type another name.
