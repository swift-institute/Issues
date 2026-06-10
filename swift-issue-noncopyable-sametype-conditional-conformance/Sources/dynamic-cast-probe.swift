import func Darwin.fflush
import var Darwin.stdout
protocol P {}
struct Pool: ~Copyable {}
struct PoolC {}
struct Gen<A: ~Copyable> {}
extension Gen: P where A == Pool {}
struct Gen2<A: ~Copyable> {}
extension Gen2: P where A == PoolC {}
struct Gen3<A: ~Copyable> {}
extension Gen3: P where A: ~Copyable {}
func say(_ s: String) { print(s); fflush(stdout) }
let a: Any = Gen<Pool>()
let b: Any = Gen2<PoolC>()
let c: Any = Gen3<Pool>()
say("dyn-cast Gen<Pool>   is P (same-type to ~Copyable, EXPECT true): \(a is any P)")
say("dyn-cast Gen2<PoolC> is P (same-type to Copyable,  EXPECT true): \(b is any P)")
say("dyn-cast Gen3<Pool>  is P (inverse-conditional,    EXPECT true): \(c is any P)")
