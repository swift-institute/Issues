// Minimal reducer: an InlineArray-backed value mutated when stored in a class field
// is DSE'd under -O. Element writes via raw pointers survive; this value-field write
// does not. Mirrors swift-buffer-slab-primitives Buffer.Slab.Inline.Box.header
// (Bit.Vector.Static = InlineArray<n,UInt>) — sparse occupancy silently lost in release.

// Variant A: InlineArray directly in a class field.
final class BoxA { var bits: InlineArray<4, UInt> = .init(repeating: 0) }

@inline(never) func runA() -> UInt {
    let b = BoxA()
    b.bits[2] = 99
    return b.bits[2]
}

// Variant B: InlineArray nested in a struct, in a class field (the real shape).
struct Inner { var storage: InlineArray<4, UInt> = .init(repeating: 0) }
struct Outer { var inner = Inner() }
final class BoxB { var outer = Outer() }

@inline(never) func runB() -> UInt {
    let b = BoxB()
    b.outer.inner.storage[2] = 99
    return b.outer.inner.storage[2]
}

// Variant C: local var (control — expected correct in both configs).
@inline(never) func runC() -> UInt {
    var s: InlineArray<4, UInt> = .init(repeating: 0)
    s[2] = 99
    return s[2]
}

print("A(class.InlineArray)=\(runA()) B(class.struct.struct.InlineArray)=\(runB()) C(local)=\(runC())")
