// t0 CONTROL: non-Tagged key (UInt) + ~Copyable value.
// Expect PASS — proves Tagged in the key slot is load-bearing (§A9 axis).
import Dictionary_Primitives
import Hash_Tagged_Primitives

struct NC: ~Copyable, Sendable { var a: Int; init(_ a: Int) { self.a = a } }

var d = Dictionary_Primitives.Dictionary<UInt, NC>()
_ = d.insert(key: UInt(7), value: NC(1))
print("t0-control (UInt key, ~Copyable value): inserted count=\(d.count) — NO CRASH")
