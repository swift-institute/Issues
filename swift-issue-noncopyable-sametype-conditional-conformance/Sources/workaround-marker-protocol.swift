import func Darwin.fflush
import var Darwin.stdout
protocol P {}
protocol Marker: ~Copyable {}
struct Pool: ~Copyable {}
extension Pool: Marker {}
struct Gen<A: ~Copyable> {}
extension Gen: P where A: Marker, A: ~Copyable {}
struct W<S: P> { var s: S; var c: Int { 42 } }
func say(_ s: String) { print(s); fflush(stdout) }
let w = W<Gen<Pool>>(s: .init())
say("constructed")
say("c = \(w.c)")
