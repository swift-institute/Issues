// t1: Tagged key (Kernel.Event.ID) + Copyable value (Int), straight-line.
// Tests §A9's open axis-C cell (institute Dictionary + Copyable value).
import Dictionary_Primitives
import ISO_9945_Core
import Hash_Tagged_Primitives

typealias K = ISO_9945.Kernel.Event.ID

var d = Dictionary_Primitives.Dictionary<K, Int>()
_ = d.insert(key: K(Int32(7)), value: 42)
print("t1 (Tagged key, Copyable Int value): inserted count=\(d.count) — NO CRASH")
