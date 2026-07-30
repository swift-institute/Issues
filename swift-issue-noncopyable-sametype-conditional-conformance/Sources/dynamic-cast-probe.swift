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
// swiftlint:disable no_any_protocol_existential
// reason: `is any P` is the exact dynamic-cast probe under test here — the bug
// being reproduced is in the runtime's handling of this existential cast
// itself, so rewriting it away would stop reproducing the defect.
say("dyn-cast Gen<Pool>   is P (same-type to ~Copyable, EXPECT true): \(a is any P)")
say("dyn-cast Gen2<PoolC> is P (same-type to Copyable,  EXPECT true): \(b is any P)")
say("dyn-cast Gen3<Pool>  is P (inverse-conditional,    EXPECT true): \(c is any P)")
// swiftlint:enable no_any_protocol_existential
