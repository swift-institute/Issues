protocol P {}
struct Pool: ~Copyable {}
struct Gen<A: ~Copyable> {}
extension Gen: P where A == Pool {}
struct W<S: P> {
    var s: S
    var c: Int { 42 }
}
import func Darwin.fflush
import var Darwin.stdout
func say(_ s: String) { print(s); fflush(stdout) }
let w = W<Gen<Pool>>(s: .init())
say("constructed")
say("c = \(w.c)")
