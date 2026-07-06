// t3: t2 shape + @escaping @Sendable closure capturing a final class holding
// the registry — mirrors Kernel.Event.Driver.init's `Shared` + `_register`.
import Dictionary_Primitives
import ISO_9945_Core
import Hash_Tagged_Primitives

typealias K = ISO_9945.Kernel.Event.ID

struct NC: ~Copyable, Sendable { var a: Int; init(_ a: Int) { self.a = a } }

final class Shared: @unchecked Sendable {
    var registry = Dictionary_Primitives.Dictionary<K, NC>()
}

let shared = Shared()
let register: @Sendable (Int) -> Void = { n in
    _ = shared.registry.insert(key: K(Int32(7)), value: NC(n))
}
register(7)
print("t3 (Tagged key, ~Copyable value, @Sendable closure on class): count=\(shared.registry.count) — NO CRASH")
