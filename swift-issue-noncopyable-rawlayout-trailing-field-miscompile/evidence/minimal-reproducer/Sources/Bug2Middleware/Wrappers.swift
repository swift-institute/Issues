// Bug2Middleware: intermediate module layer for Bug 2 reproducer
//
// Wraps Bug2PropertyLib types to add another layer of cross-module
// SIL serialization.

public import Bug2PropertyLib

// ── Wrapper that uses SmallBuffer with ~Copyable elements ───────────

public struct Collection: ~Copyable {
    @usableFromInline
    var _buffer: SmallBuffer<NCElement>

    @inlinable
    public init() {
        self._buffer = SmallBuffer()
    }

    @inlinable
    public mutating func add(_ value: Int) {
        _buffer.append(NCElement(value))
    }

    @inlinable
    public mutating func drainAll(_ body: (consuming NCElement) -> Void) {
        _buffer.drain(body)
    }
}

// ── @inlinable function cascading SIL through the middleware ────────

@inlinable
public func buildAndDrain() {
    var col = Collection()
    col.add(10)
    col.add(20)
    col.add(30)
    col.drainAll { print($0.value) }
}
