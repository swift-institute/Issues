// repro.swift — faithful cross-module model of the input crash.
//
// Drop into a SwiftPM target that depends on swift-iterator-primitives products
// "Iterator Chunk Primitives" + "Iterable", with the ecosystem swift settings
// (Lifetimes, LifetimeDependence, SuppressedAssociatedTypes, NonisolatedNonsendingByDefault,
//  InternalImportsByDefault, MemberImportVisibility, InferIsolatedConformances, strictMemorySafety).
//
// CRASH (Swift 6.3.2 +Asserts, e.g. the Windows 6.3.2-RELEASE toolchain), during
// type-checking the IteratorProtocol half of the dual conformance:
//
//   Assertion failed: getEffects(req).contains(getEffects(witness)) &&
//       "witness has more effects than requirement?",
//       lib/Sema/TypeCheckProtocol.cpp, line 1311
//   While evaluating request ResolveValueWitnessesRequest(
//       TestColl<Element>.Iterator: IteratorProtocol)
//
// NOTE: this is a +Asserts-only Sema assertion. It does NOT fire on NoAsserts RELEASE
// toolchains (stock macOS/Linux) — that is why those CI legs pass. It is FIXED on
// Swift 6.5-dev (this exact code, and the real swift-input-primitives test target,
// build clean there). No local 6.3.2 +Asserts toolchain was available to reproduce
// the assertion outside Windows CI; the Windows CI run is the reproduction of record.

public import Iterator_Chunk_Primitives
public import Iterable

struct TestColl<Element: Sendable>: Sendable {
    var storage: [Element]
}

extension TestColl: Iterable {
    borrowing func makeIterator() -> Iterator {
        Iterator(offset: 0, storage: storage)
    }
}

extension TestColl {
    struct Iterator {
        var offset: Int
        let storage: [Element]
        var _element: Element? = nil
    }
}

// The crashing declaration: a single extension co-conforms the nested Iterator to
// BOTH the custom Span-returning chunk protocol AND stdlib IteratorProtocol.
extension TestColl.Iterator: Iterator.Chunk.`Protocol`, IteratorProtocol {
    typealias Failure = Never

    @_lifetime(&self)
    mutating func next(maximumCount: some Carrier.`Protocol`<Cardinal>) -> Span<Element> {
        let ptr = unsafe withUnsafeMutablePointer(to: &_element) { p in
            unsafe UnsafePointer<Element>(
                unsafe UnsafeRawPointer(p).assumingMemoryBound(to: Element.self)
            )
        }
        guard maximumCount.underlying > .zero else {
            let span = unsafe Span(_unsafeStart: ptr, count: 0)
            return unsafe _overrideLifetime(span, mutating: &self)
        }
        guard let value = next() else {
            let span = unsafe Span(_unsafeStart: ptr, count: 0)
            return unsafe _overrideLifetime(span, mutating: &self)
        }
        _element = value
        let span = unsafe Span(_unsafeStart: ptr, count: 1)
        return unsafe _overrideLifetime(span, mutating: &self)
    }

    mutating func next() -> Element? {
        guard offset < storage.count else { return nil }
        let element = storage[offset]
        offset += 1
        return element
    }
}
