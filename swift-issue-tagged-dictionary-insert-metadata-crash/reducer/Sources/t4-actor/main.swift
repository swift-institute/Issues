// t4: t3 shape but the insert runs inside a detached Task on the cooperative
// executor — mirrors the crash queue `com.apple.root.default-qos.cooperative`.
import Dictionary_Primitives
import ISO_9945_Core
import Hash_Tagged_Primitives

typealias K = ISO_9945.Kernel.Event.ID

struct NC: ~Copyable, Sendable { var a: Int; init(_ a: Int) { self.a = a } }

final class Shared: @unchecked Sendable {
    var registry = Dictionary_Primitives.Dictionary<K, NC>()
}

let shared = Shared()
await Task.detached {
    _ = shared.registry.insert(key: K(Int32(7)), value: NC(1))
}.value
print("t4 (Tagged key, ~Copyable value, detached cooperative Task): count=\(shared.registry.count) — NO CRASH")
