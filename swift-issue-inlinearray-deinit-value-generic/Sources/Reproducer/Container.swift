// Minimal reproduction of InlineArray deinit bug with value generic parameter.
//
// Bug: When a ~Copyable struct uses `InlineArray<capacity, ...>` where `capacity`
// is a value generic parameter, and contains only value-type properties, the
// compiler fails to generate deinit dispatch for cross-module ~Copyable elements.
// Elements are silently leaked.

// MARK: - Buggy: InlineArray with value generic capacity

/// This container silently leaks ~Copyable elements defined in other modules.
public struct Container<Element: ~Copyable, let capacity: Int>: ~Copyable {
    var _storage: InlineArray<capacity, (Int, Int, Int, Int, Int, Int, Int, Int)>
    var _count: Int
    // NO reference type properties - this is the buggy configuration

    public init() {
        self._storage = InlineArray(repeating: (0, 0, 0, 0, 0, 0, 0, 0))
        self._count = 0
    }

    @unsafe
    mutating func _pointerToElement(at index: Int) -> UnsafeMutablePointer<Element> {
        let stride = MemoryLayout<Element>.stride
        return unsafe Swift.withUnsafeMutablePointer(to: &_storage) { storagePtr in
            let basePtr = UnsafeMutableRawPointer(storagePtr)
            return unsafe (basePtr + index * stride).assumingMemoryBound(to: Element.self)
        }
    }

    public mutating func push(_ element: consuming Element) {
        precondition(_count < capacity, "Container is full")
        unsafe _pointerToElement(at: _count).initialize(to: element)
        _count += 1
    }

    deinit {
        // This deinit IS executed, but element deinitializers are NOT called
        // for cross-module ~Copyable elements when struct has only value-type properties
        let count = _count
        guard count > 0 else { return }
        let stride = MemoryLayout<Element>.stride
        unsafe Swift.withUnsafeBytes(of: _storage) { bytes in
            let basePtr = unsafe UnsafeMutableRawPointer(mutating: bytes.baseAddress!)
            for i in 0..<count {
                let elementPtr = unsafe (basePtr + i * stride).assumingMemoryBound(to: Element.self)
                unsafe elementPtr.deinitialize(count: 1)  // Element.deinit NOT called!
            }
        }
    }
}

// MARK: - Fixed: Same but with AnyObject? workaround

/// This container correctly calls deinit on ~Copyable elements.
public struct ContainerFixed<Element: ~Copyable, let capacity: Int>: ~Copyable {
    var _storage: InlineArray<capacity, (Int, Int, Int, Int, Int, Int, Int, Int)>
    var _count: Int
    // WORKAROUND: Reference type property
    // WHY: forces the enclosing struct to carry a class-typed field, which
    //   sidesteps the value-generic InlineArray deinit-elision bug this
    //   reproducer demonstrates on the unfixed Container above.
    // WHEN TO REMOVE: once the upstream compiler defect (deinit not invoked
    //   for InlineArray<capacity, Element> fields under a value-generic
    //   capacity) is fixed and this repository's reproducer is closed.
    // TRACKING: this reproducer's own tracking issue in swift-institute/Issues.
    var _deinitWorkaround: AnyObject? = nil

    public init() {
        self._storage = InlineArray(repeating: (0, 0, 0, 0, 0, 0, 0, 0))
        self._count = 0
    }

    @unsafe
    mutating func _pointerToElement(at index: Int) -> UnsafeMutablePointer<Element> {
        let stride = MemoryLayout<Element>.stride
        return unsafe Swift.withUnsafeMutablePointer(to: &_storage) { storagePtr in
            let basePtr = UnsafeMutableRawPointer(storagePtr)
            return unsafe (basePtr + index * stride).assumingMemoryBound(to: Element.self)
        }
    }

    public mutating func push(_ element: consuming Element) {
        precondition(_count < capacity, "Container is full")
        unsafe _pointerToElement(at: _count).initialize(to: element)
        _count += 1
    }

    deinit {
        let count = _count
        guard count > 0 else { return }
        let stride = MemoryLayout<Element>.stride
        unsafe Swift.withUnsafeBytes(of: _storage) { bytes in
            let basePtr = unsafe UnsafeMutableRawPointer(mutating: bytes.baseAddress!)
            for i in 0..<count {
                let elementPtr = unsafe (basePtr + i * stride).assumingMemoryBound(to: Element.self)
                unsafe elementPtr.deinitialize(count: 1)  // Element.deinit IS called
            }
        }
    }
}

// MARK: - Control: InlineArray with literal capacity (works correctly)

/// This container works correctly - literal capacity does not trigger the bug.
public struct ContainerLiteral<Element: ~Copyable>: ~Copyable {
    var _storage: InlineArray<4, (Int, Int, Int, Int, Int, Int, Int, Int)>  // Literal 4, not generic
    var _count: Int
    // NO reference type properties - but still works!

    public init() {
        self._storage = InlineArray(repeating: (0, 0, 0, 0, 0, 0, 0, 0))
        self._count = 0
    }

    @unsafe
    mutating func _pointerToElement(at index: Int) -> UnsafeMutablePointer<Element> {
        let stride = MemoryLayout<Element>.stride
        return unsafe Swift.withUnsafeMutablePointer(to: &_storage) { storagePtr in
            let basePtr = UnsafeMutableRawPointer(storagePtr)
            return unsafe (basePtr + index * stride).assumingMemoryBound(to: Element.self)
        }
    }

    public mutating func push(_ element: consuming Element) {
        precondition(_count < 4, "Container is full")
        unsafe _pointerToElement(at: _count).initialize(to: element)
        _count += 1
    }

    deinit {
        let count = _count
        guard count > 0 else { return }
        let stride = MemoryLayout<Element>.stride
        unsafe Swift.withUnsafeBytes(of: _storage) { bytes in
            let basePtr = unsafe UnsafeMutableRawPointer(mutating: bytes.baseAddress!)
            for i in 0..<count {
                let elementPtr = unsafe (basePtr + i * stride).assumingMemoryBound(to: Element.self)
                unsafe elementPtr.deinitialize(count: 1)  // Element.deinit IS called
            }
        }
    }
}
