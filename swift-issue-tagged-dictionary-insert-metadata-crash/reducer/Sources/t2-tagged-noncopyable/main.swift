// t2: Tagged key (Kernel.Event.ID) + ~Copyable value, straight-line.
// Hypothesised MINIMAL trigger (mirrors §A9's 3-line Set.Ordered<Tagged> reducer).
import Dictionary_Primitives
import ISO_9945_Core
import Hash_Tagged_Primitives

typealias K = ISO_9945.Kernel.Event.ID

struct NC: ~Copyable, Sendable { var a: Int; init(_ a: Int) { self.a = a } }

var d = Dictionary_Primitives.Dictionary<K, NC>()
_ = d.insert(key: K(Int32(7)), value: NC(1))
print("t2 (Tagged key, ~Copyable value): inserted count=\(d.count) — NO CRASH")
