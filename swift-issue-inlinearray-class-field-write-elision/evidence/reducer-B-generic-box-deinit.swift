// Closer reducer: generic class Box over a ~Copyable substrate, holding an InlineArray-
// backed bitmap (word/mask RMW, like Bit.Vector.Static) + a deinit that READS the bitmap
// (the teardown-liveness shape). Mutation reaches it through a ~Copyable wrapper struct's
// mutating method. Mirrors Buffer.Slab.Inline (Box.header) → checking the -O DSE.

struct Bits {
    var words: InlineArray<1, UInt> = .init(repeating: 0)
    subscript(i: Int) -> Bool {
        get { (words[0] & (1 << UInt(i))) != 0 }
        set { if newValue { words[0] |= (1 << UInt(i)) } else { words[0] &= ~(1 << UInt(i)) } }
    }
    var popcount: Int { words[0].nonzeroBitCount }
}

struct Raw: ~Copyable { var x: Int = 0 }   // stand-in for the @_rawLayout substrate

final class Box<S: ~Copyable> {
    var bits = Bits()
    var sub: S
    init(_ sub: consuming S) { self.sub = sub }
    deinit {
        // teardown reads the bitmap (occupancy-walk liveness)
        if bits[2] { /* would drain */ }
    }
    func mark(_ i: Int) { bits[i] = true }
}

struct Wrapper<S: ~Copyable>: ~Copyable {
    var box: Box<S>
    init(_ sub: consuming S) { self.box = Box(sub) }
    mutating func insert(_ i: Int) { box.mark(i) }
    var occupancy: Int { box.bits.popcount }
}

@inline(never) func run() -> Int {
    var w = Wrapper<Raw>(Raw())
    w.insert(2)
    return w.occupancy
}
print("occupancy=\(run()) (expect 1)")
