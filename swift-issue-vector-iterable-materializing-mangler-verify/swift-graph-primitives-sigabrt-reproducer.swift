// Standalone reproducer for swift-graph-primitives EarlyPerfInliner SIGABRT
//
// Reproduces:
//   Abort: function demangleAndAddAsChildren at GenericSpecializationMangler.cpp:47
//   Can't demangle: <nested-namespace mangled substring>
//
// Build: swiftc -O reproducer.swift -o /tmp/repro
// Crashes in: SILFunctionTransform "EarlyPerfInliner" while specializing a function
// whose parent-function debug-info name embeds a generic-specialization that
// references nested-protocol types via `\`Protocol\`` lookalike-keyword names.

// MARK: - Hash.Protocol (capability protocol nested in namespace enum)

public enum Hash {
    public protocol `Protocol`: ~Copyable {
        borrowing func hash(into hasher: inout Hasher)
    }
}

// MARK: - Ordinal namespace + nested \`Protocol\`

public enum Ordinal_NS {
    public protocol `Protocol`: ~Copyable {
        var ordinal: Ordinal_NS.Value { get }
        init(_ ordinal: Ordinal_NS.Value)
    }

    public struct Value: Hash.`Protocol`, Equatable, Hashable {
        public let raw: UInt
        public init(_ raw: UInt) { self.raw = raw }
        public func hash(into hasher: inout Hasher) { hasher.combine(raw) }
    }
}

extension Ordinal_NS.Value: Ordinal_NS.`Protocol` {
    public var ordinal: Ordinal_NS.Value { self }
    public init(_ ordinal: Ordinal_NS.Value) { self = ordinal }
}

// MARK: - Tagged<Tag, Underlying>  (no ~Escapable to keep reproducer simple)

@frozen
public struct Tagged<Tag: ~Copyable, Underlying: ~Copyable>: ~Copyable {
    public var underlying: Underlying

    public init(_unchecked underlying: consuming Underlying) {
        self.underlying = underlying
    }
}

extension Tagged: Copyable where Tag: ~Copyable, Underlying: Copyable {}
extension Tagged: Sendable
where Tag: ~Copyable, Underlying: ~Copyable & Sendable {}
extension Tagged: Equatable
where Tag: ~Copyable, Underlying: Equatable {}
extension Tagged: Hashable
where Tag: ~Copyable, Underlying: Hashable {}

// Hash.\`Protocol\` conformance for Tagged
extension Tagged: Hash.`Protocol` where Tag: ~Copyable, Underlying: ~Copyable & Hash.`Protocol` {
    @inlinable
    @_disfavoredOverload
    public borrowing func hash(into hasher: inout Hasher) {
        underlying.hash(into: &hasher)
    }
}

// Ordinal.\`Protocol\` conformance for Tagged
extension Tagged: Ordinal_NS.`Protocol`
where Underlying: Ordinal_NS.`Protocol`, Tag: ~Copyable {
    public var ordinal: Ordinal_NS.Value { underlying.ordinal }

    @_disfavoredOverload
    @inlinable
    public init(_ ordinal: Ordinal_NS.Value) {
        self.init(_unchecked: Underlying(ordinal))
    }
}

// MARK: - Index<Element> typealias to Tagged<Element, Ordinal_NS.Value>

public typealias Index<Element: ~Copyable> = Tagged<Element, Ordinal_NS.Value>

// MARK: - Set<Element>.Ordered

public enum SetNS<Element: Hash.`Protocol` & ~Copyable>: ~Copyable {

    public struct Ordered where Element: Copyable {
        @usableFromInline
        var storage: [Element]

        @inlinable
        public init() { self.storage = [] }

        @inlinable
        public init(_ storage: [Element]) { self.storage = storage }

        @inlinable
        public func forEach<E: Swift.Error>(_ body: (borrowing Element) throws(E) -> Void) throws(E) {
            let count = storage.count
            guard count > 0 else { return }
            var i = 0
            while i < count {
                try body(storage[i])
                i += 1
            }
        }
    }
}

// MARK: - Graph namespace

public enum Graph {
    public typealias Node<Tag> = Index<Tag>

    public enum Sequential<Tag, Payload> {
        public struct Transform {
            public init() {}
        }
    }
}

// MARK: - The crashing function

extension Graph.Sequential.Transform {
    /// The shape that triggers the crash:
    ///   - generic over `Adjacent: Sequence`
    ///   - parameter is `consuming SetNS<Tagged<Tag, Ordinal>>.Ordered`
    ///   - body invokes `nodes.forEach { ... }` which the inliner specializes
    @inlinable
    public func subgraph<Adjacent: Swift.Sequence<Graph.Node<Tag>>>(
        inducedBy nodes: consuming SetNS<Graph.Node<Tag>>.Ordered,
        adjacents: (Payload) -> Adjacent
    ) -> Int {
        var count = 0
        nodes.forEach { node in
            count += 1
            _ = node
        }
        return count
    }
}

// Concrete entry point so EarlyPerfInliner has reason to specialize
public enum MyTag {}
public struct MyPayload {
    public init() {}
}

@inline(never)
public func driver(set: SetNS<Graph.Node<MyTag>>.Ordered, payload: MyPayload) -> Int {
    let t = Graph.Sequential<MyTag, MyPayload>.Transform()
    return t.subgraph(inducedBy: set, adjacents: { _ in [Graph.Node<MyTag>]() })
}
