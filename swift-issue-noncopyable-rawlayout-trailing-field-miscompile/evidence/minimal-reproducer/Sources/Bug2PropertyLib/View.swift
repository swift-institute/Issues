// Bug2PropertyLib: Types that trigger CopyPropagation crash
//
// Imports Bug1Core for @_rawLayout types. The crash occurs when
// CopyPropagation cannot model ownership of ~Copyable values in
// loops with conditional moves or enum switches with multiple
// consuming operations.

public import Bug1Core

// ── ~Copyable element type ──────────────────────────────────────────

public struct NCElement: ~Copyable, @unchecked Sendable {
    public var value: Int

    @inlinable
    public init(_ value: Int) {
        self.value = value
    }

    deinit {}
}

// ── Heap storage ────────────────────────────────────────────────────

public final class HeapStorage<Element: ~Copyable>: @unchecked Sendable {
    @usableFromInline
    let _buffer: UnsafeMutablePointer<Element>

    @usableFromInline
    var _count: Int

    @usableFromInline
    let _capacity: Int

    @inlinable
    public init(capacity: Int) {
        self._buffer = .allocate(capacity: capacity)
        self._count = 0
        self._capacity = capacity
    }

    @inlinable
    public var count: Int { _count }

    @inlinable
    public func append(_ element: consuming Element) {
        unsafe _buffer.advanced(by: _count).initialize(to: element)
        _count += 1
    }

    @inlinable
    public func move(at index: Int) -> Element {
        unsafe _buffer.advanced(by: index).move()
    }

    deinit {
        for i in 0..<_count {
            unsafe _buffer.advanced(by: i).deinitialize(count: 1)
        }
        _buffer.deallocate()
    }
}

// ── Buffer backed by @_rawLayout (from Bug1Core) ────────────────────
// Stores @_rawLayout type from cross-module, creating the serialized
// SIL context that interacts with CopyPropagation.

public struct InlineBuffer<Element: ~Copyable>: ~Copyable {
    @usableFromInline
    var _storage: Container<Element>.Inline<8>

    @usableFromInline
    var _bitmap: UInt64

    @inlinable
    public init() {
        self._storage = Container<Element>.Inline<8>()
        self._bitmap = 0
    }

    @inlinable
    public func isOccupied(_ index: Int) -> Bool {
        (_bitmap >> index) & 1 == 1
    }
}

// ── Small buffer with enum and @_rawLayout SIL in scope ─────────────

public struct SmallBuffer<Element: ~Copyable>: ~Copyable {
    @frozen
    public enum _Representation: ~Copyable {
        case inline(InlineBuffer<Element>)
        case heap(HeapStorage<Element>)
    }

    @usableFromInline
    var _storage: _Representation

    @inlinable
    public init() {
        self._storage = .inline(InlineBuffer())
    }

    @inlinable
    init(_storage: consuming _Representation) {
        self._storage = consume _storage
    }

    /// Consuming element inside enum switch — triggers CopyPropagation.
    @inlinable
    public mutating func append(_ element: consuming Element) {
        switch _storage {
        case .inline(var buf):
            // Spill to heap — consumes both buf and element
            let heap = HeapStorage<Element>(capacity: 16)
            heap.append(element)
            self = SmallBuffer(_storage: .heap(heap))
            _ = consume buf
        case .heap(let heap):
            heap.append(element)
            self = SmallBuffer(_storage: .heap(heap))
        }
    }

    @inlinable
    public mutating func drain(_ body: (consuming Element) -> Void) {
        switch _storage {
        case .inline(var buf):
            // Bitmap-conditional move in a loop
            for i in 0..<8 {
                if buf.isOccupied(i) {
                    // Would need Builtin access to actually move from @_rawLayout
                    // but the SIL pattern is generated regardless
                    buf._bitmap &= ~(1 << i)
                }
            }
            self = SmallBuffer(_storage: .inline(consume buf))
        case .heap(let heap):
            for i in 0..<heap.count {
                body(heap.move(at: i))
            }
            heap._count = 0
            self = SmallBuffer(_storage: .heap(heap))
        }
    }
}
