// Reproducer — CONSUMER module `N` (models swift-vector-primitives "Vector Primitives" ops
// module: Vector+Iterable.swift + Vector+Sequenceable.swift + Vector+Sequence.Properties.swift).
//
// PASSES on NoAsserts (macOS/Linux). Aborts at Mangler.cpp:176 on a +Asserts toolchain
// (Windows 6.3.x, or the swiftlang/swift:nightly-6.3-jammy Linux image). The crashing symbol
// is `iterableMakeIterator` (the Iterable @_implements witness) — see CHARACTERIZATION.md.
//
//   swiftc -swift-version 6 -enable-experimental-feature SuppressedAssociatedTypes \
//          -enable-experimental-feature Lifetimes -wmo -parse-as-library \
//          -emit-module -emit-module-path M.swiftmodule -module-name M defining.swift
//   swiftc -swift-version 6 -enable-experimental-feature SuppressedAssociatedTypes \
//          -enable-experimental-feature Lifetimes -wmo -parse-as-library \
//          -c consumer.swift -I . -module-name N -o n.o

public import M

// (Vector+Iterable.swift:38) scalar Iterator conforms to scalar IterP AND stdlib IteratorProtocol.
extension Vec.Iterator: IterP, Swift.IteratorProtocol where Bound: Copyable {}

// (Vector+Iterable.swift:56) the DUAL makeIterator: ops-module borrowing one coexisting with the
// type module's consuming one.
extension Vec where Bound: Copyable {
    @inlinable
    public borrowing func makeIterator() -> Iterator {
        _makeSequenceIterator()
    }
}

// (Vector+Iterable.swift:75-97) Iterable conformance with the @_implements split: Iterable.Iterator
// is bound to the nested-generic Mat<Vec.Iterator> (Materializing<Vector.Iterator>). The mangled
// name of iterableMakeIterator is what the +Asserts mangler emits but cannot re-demangle.
extension Vec: Iterable2 where Bound: Copyable {
    @_implements(Iterable2, Iterator)
    public typealias IterableIterator = Mat<Iterator>

    @inlinable
    @_lifetime(borrow self)
    @_implements(Iterable2, makeIterator())
    public borrowing func iterableMakeIterator() -> Mat<Iterator> {
        let scalar: Iterator = makeIterator()
        return Mat(scalar)
    }
}

// (Vector+Sequenceable.swift:33) Sequenceable — the handoff's presumed trigger. NOT the cause:
// removing it leaves the crash; removing the Iterable conformance above removes the crash.
extension Vec: Seqable where Bound: Copyable {}

// (Vector+Iterable.swift:141) Swift.Sequence (pre-existing).
extension Vec: Swift.Sequence where Bound: Copyable {
    @inlinable
    public var underestimatedCount: Int { count }
}
