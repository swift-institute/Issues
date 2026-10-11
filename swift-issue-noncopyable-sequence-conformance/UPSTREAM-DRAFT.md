# Draft for swiftlang/swift (not filed)

Status: not to be filed. Coen ruled on 2026-10-11 that there are no new upstream filings; this record in swift-institute/Issues is the report. The text below is kept for reference.

Duplicate search (2026-10-11): swiftlang/swift#87448 is the nearest report. Its original case was answered as intended under SE-0427: there the extension lacks `where T: ~Copyable`. This case has that clause and depends on declaration order and access level. Coen described the trigger in a comment on #87448 in January, but nobody has answered that part.

---

**Title:** Conformance declared before a public nested ~Copyable type makes its stored property require Copyable

### Description

A conditional conformance to a protocol with an associated type named `Element` is declared before a `public` nested `~Copyable` type. The type's own generic context is `where Element: ~Copyable`. Its stored property is then rejected with "type 'Element' does not conform to protocol 'Copyable'". Declaring the conformance after the type, making the types internal, or renaming the associated type all compile.

### Reproduction

```swift
protocol P {
    associatedtype Element
}

extension Outer.Inner: P where Element: Copyable {}

public enum Outer<Element: ~Copyable> {}

extension Outer where Element: ~Copyable {
    public struct Inner: ~Copyable {
        var storage: Box<Element>
    }
}

extension Outer.Inner: Copyable where Element: Copyable {}

final class Box<Element: ~Copyable> {}
```

```
$ swiftc -swift-version 6 -parse-as-library -c Reduced.swift
Reduced.swift:11:26: error: type 'Element' does not conform to protocol 'Copyable'
 9 | extension Outer where Element: ~Copyable {
10 |     public struct Inner: ~Copyable {
11 |         var storage: Box<Element>
   |                          `- error: type 'Element' does not conform to protocol 'Copyable'
12 |     }
13 | }
```

`-typecheck` alone is clean. In a package, the same thing happens when the conformance is in a file that sorts first (`Outer.Inner+P.swift` before `Outer.Inner.swift`).

### Expected behavior

It compiles. The struct is declared in `extension Outer where Element: ~Copyable`, and the conformance's `where Element: Copyable` should only constrain the conformance.

### Environment

- Apple Swift 6.4 (swiftlang-6.4.0.34.1), arm64-apple-macosx27.2.0
- Also reproduces on swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a and swift-DEVELOPMENT-SNAPSHOT-2026-07-11-a (6.5-dev)
