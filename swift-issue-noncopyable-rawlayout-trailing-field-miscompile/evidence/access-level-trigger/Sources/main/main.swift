// Toolchain: Swift 6.3.1 (2026-04-30) — anchor added during Phase 7a sweep [EXP-007a]
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL CRASHES
//
@_rawLayout(likeArrayOf: Element, count: capacity)
public struct RawElements<Element: ~Copyable, let capacity: Int>: ~Copyable {
    public init() {}
}

public struct CombinedLayout<Element: ~Copyable, let capacity: Int>: ~Copyable {
    public var elements: RawElements<Element, capacity>
    public var bitmap: InlineArray<4, UInt>
}

@_rawLayout(like: CombinedLayout<Element, capacity>)
public struct CombinedRaw<Element: ~Copyable, let capacity: Int>: ~Copyable {
    public init() {}
}

public struct InlineStorage<Element: ~Copyable, let capacity: Int>: ~Copyable {
    public var _raw: CombinedRaw<Element, capacity>

    public init() { _raw = CombinedRaw() }

    deinit {
        let stride = MemoryLayout<Element>.stride
        let bitmapOffset = stride * capacity
        unsafe withUnsafePointer(to: _raw) { rawBase in
            let base = unsafe UnsafeRawPointer(rawBase)
            let bitmapPtr = unsafe base.advanced(by: bitmapOffset)
                .assumingMemoryBound(to: UInt.self)
            let elementBase = unsafe UnsafeMutableRawPointer(mutating: base)
            for word in 0..<4 {
                var bits = unsafe bitmapPtr[word]
                while bits != 0 {
                    let bitIdx = bits.trailingZeroBitCount
                    let slot = word &* UInt.bitWidth &+ bitIdx
                    guard slot < capacity else { break }
                    unsafe elementBase.advanced(by: slot &* stride)
                        .assumingMemoryBound(to: Element.self)
                        .deinitialize(count: 1)
                    bits &= bits &- 1
                }
            }
        }
    }
}

print("OK")
