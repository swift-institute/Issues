// Module M — defining module.
// Mirrors: swift-iterator-primitives (Iterator.`Protocol` scalar, __IteratorChunkProtocol
// bulk, Iterable, Materializing), swift-sequence-primitives (Sequenceable), and
// swift-vector-primitives "Vector Primitive" type module.

// MARK: - scalar iterator protocol (mirrors Iterator.`Protocol`)

public protocol IterP<Element, Failure>: ~Copyable, ~Escapable {
    associatedtype Element: ~Copyable & ~Escapable
    associatedtype Failure: Swift.Error = Never
    @_lifetime(&self)
    mutating func next() throws(Failure) -> Element?
}

// MARK: - bulk/chunk iterator protocol (mirrors __IteratorChunkProtocol) — DISTINCT from
// the scalar IterP. The two protocols having different bounds is what lets the @_implements
// associated-type split disambiguate on a dual conformer.

public protocol ChunkP<Element, Failure>: ~Copyable, ~Escapable {
    associatedtype Element: ~Copyable & ~Escapable
    associatedtype Failure: Swift.Error = Never
    @_lifetime(&self)
    mutating func nextChunk() throws(Failure) -> Element?
}

// MARK: - Sequenceable (single-pass, consuming) — mirrors Sequenceable

public protocol Seqable<Element>: ~Copyable, ~Escapable {
    associatedtype Element: ~Copyable & ~Escapable
    associatedtype Iterator: IterP, ~Copyable, ~Escapable where Iterator.Element == Element
    @_lifetime(copy self)
    consuming func makeIterator() -> Iterator
}

// MARK: - Iterable (multipass, borrowing) — mirrors Iterable. Its `Iterator` associatedtype
// is ALSO named `Iterator` but bound to the bulk ChunkP (≠ Seqable's scalar IterP).

public protocol Iterable2: ~Copyable, ~Escapable {
    associatedtype Iterator: ChunkP, ~Copyable, ~Escapable
    @_lifetime(borrow self)
    borrowing func makeIterator() -> Iterator
}

// MARK: - Materializing adapter (mirrors Iterator.Materializing<Base>) — wraps a scalar
// IterP and presents as a bulk ChunkP. The @_implements target for Iterable.Iterator.

public struct Mat<Base: IterP & ~Copyable & ~Escapable>: ~Copyable, ~Escapable {
    @usableFromInline var base: Base
    @inlinable
    @_lifetime(copy base)
    public init(_ base: consuming Base) { self.base = base }
}

extension Mat: ChunkP {
    public typealias Element = Base.Element
    public typealias Failure = Base.Failure
    @_lifetime(&self)
    @inlinable
    public mutating func nextChunk() throws(Failure) -> Element? {
        try base.next()
    }
}

// MARK: - Vec type (mirrors Vector<Bound>)

public struct Vec<Bound: ~Copyable> {
    @usableFromInline var start: Int
    @usableFromInline var end: Int
    @usableFromInline let transform: @Sendable (Int) -> Bound

    @inlinable
    public init(start: Int, end: Int, transform: @escaping @Sendable (Int) -> Bound) {
        self.start = start
        self.end = end
        self.transform = transform
    }

    @inlinable
    public var count: Int { end - start }

    // Nested iterator (mirrors Vector.Iterator: ~Copyable, hand-written scalar cursor)
    public struct Iterator: ~Copyable {
        @usableFromInline var current: Int
        @usableFromInline let end: Int
        @usableFromInline let transform: @Sendable (Int) -> Bound

        @inlinable
        // swift-linter:disable:next inlinable internal access
        // REASON: This internal initializer is part of the cross-module mangler reproducer; changing its visibility alters the compiler trigger's access surface.
        init(current: Int, end: Int, transform: @escaping @Sendable (Int) -> Bound) {
            self.current = current
            self.end = end
            self.transform = transform
        }

        @inlinable
        public mutating func next() -> Bound? {
            guard current < end else { return nil }
            let result = transform(current)
            current += 1
            return result
        }
    }

    // type-module consuming makeIterator (mirrors Vector.swift:456)
    @inlinable
    public consuming func makeIterator() -> Iterator {
        Iterator(current: start, end: end, transform: transform)
    }

    // package-window-equivalent (mirrors _makeSequenceIterator)
    @inlinable
    public borrowing func _makeSequenceIterator() -> Iterator {
        Iterator(current: start, end: end, transform: transform)
    }
}

extension Vec.Iterator: Copyable where Bound: Copyable {}
extension Vec: Sendable where Bound: Sendable {}
extension Vec.Iterator: Sendable where Bound: Sendable {}
