// Reducer v3: InlineArray bitmap SIBLING to a @_rawLayout field in the same class box
// (the real Box holds Header.Static[InlineArray] + Store.Inline[@_rawLayout]). Tests
// whether the @_rawLayout sibling confounds -O field-liveness for the InlineArray write.
struct Bits {
    var words: InlineArray<1, UInt> = .init(repeating: 0)
    subscript(i: Int) -> Bool {
        get { (words[0] & (1 << UInt(i))) != 0 }
        set { if newValue { words[0] |= (1 << UInt(i)) } else { words[0] &= ~(1 << UInt(i)) } }
    }
    var popcount: Int { words[0].nonzeroBitCount }
}
@_rawLayout(likeArrayOf: Int, count: 4)
struct RawInline: ~Copyable { init() {} }

final class Box {
    var bits = Bits()
    var raw = RawInline()
    init() {}
    deinit { if bits[2] { _ = 0 } }
    func mark(_ i: Int) { bits[i] = true }
}
struct Wrapper: ~Copyable {
    var box = Box()
    mutating func insert(_ i: Int) { box.mark(i) }
    var occupancy: Int { box.bits.popcount }
}
@inline(never) func run() -> Int { var w = Wrapper(); w.insert(2); return w.occupancy }
print("occupancy=\(run()) (expect 1)")
