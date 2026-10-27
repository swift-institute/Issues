# value-generic-nested-generic-metadata-crash

Runtime SIGSEGV in `libswiftCore` when generic metadata is instantiated for a
**generic type nested inside a value-generic (`let N: Int`) type**.

Tracking record: `swift-institute/Issues#105`.

## Reduction

```swift
enum Link<let N: Int> {}

extension Link {
    struct Node<Element> {
        var element: Element
    }
}

print(_typeName(Link<1>.Node<Int>.self))
```

That is the whole trigger. `Sources/main.swift` carries the full A/B record.

## Invocation

```sh
cd Experiments/value-generic-nested-generic-metadata-crash
rm -rf .build
swift run -c debug
```

## Expected vs actual

| | |
|---|---|
| Expected | prints `value_generic_nested_generic_metadata_crash.Link<1>.Node<Swift.Int>`, exit 0 (this is what Swift 6.3.3 does) |
| Actual | SIGSEGV, exit 139, `Bad pointer dereference at 0x0000000000000000` inside `libswiftCore` |

`swift build` **succeeds**. The defect is in the runtime, not the compiler, so
the crash appears only when the program runs.

## Toolchain identity

| Toolchain | Platform | Result |
|---|---|---|
| Swift 6.3.3 (`swift-6.3.3-RELEASE`) | linux/arm64 | **passes** |
| Swift 6.4-dev (`swiftlang/swift@sha256:8d614165059587ce9dcf6727a76aeff4cbf1cde41fde9a9281a43803be736224`, noble, +assertions) | linux/amd64 | **crashes** |
| same image | linux/arm64 | **crashes** |
| Apple Swift 6.4 (`swiftlang-6.4.0.27.1`) | macOS arm64 | **crashes** |
| Swift 6.5-dev main nightly (`swiftlang/swift:nightly-main-noble`) | linux/arm64 | **crashes** |

A regression after 6.3.3, still present at main. Not platform-specific — it
reproduces on Linux on both architectures and on macOS.

## Required ingredients

Each proven by an A/B pair — A crashes, B removes only that ingredient and
passes:

1. the parent type is **value-generic** (a type-generic parent passes);
2. the nested type is **itself generic** (a non-generic nested type passes);
3. the type is **nested** (hoisting the value generic onto the type passes);
4. metadata is requested **at run time** (under `-O` this shape's metadata is
   emitted statically and the crash does not fire).

`~Copyable`, `InlineArray`, self-referential generic arguments, phantom-tag
wrappers, Swift Testing, and release mode are all **incidental** — each was
removed and the crash persisted.

## Root-cause hypothesis

The runtime's type decoder binds the parent's value-generic argument to a
generic-parameter slot that expects a type. The 6.5-dev runtime states it
directly before dying:

```
failed type lookup for <module>.Link<1>.Node<Swift.Int>:
TypeDecoder.h:788: Node kind 246 "" -
integer value bound to non-value generic parameter
```

On 6.4 the same mis-decode is silent and reaches a null dereference. In release
builds it surfaces as a metadata-completion frame for an unrelated stdlib type
with an empty generic argument list (`ClosedRange<>.Index`) — the mis-decoded
descriptor showing through.

## Recheck condition

Re-run this package at the next toolchain drop. The defect clears when
`swift run -c debug` prints the type name and exits 0 on a 6.4-or-later
release toolchain.
