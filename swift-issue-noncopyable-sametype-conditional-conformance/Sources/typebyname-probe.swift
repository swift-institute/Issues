import func Darwin.fflush
import var Darwin.stdout
struct Pool: ~Copyable {}
struct CopyablePayload {}
struct Gen<A: ~Copyable> {}
struct PlainGen<A> {}

func say(_ s: String) { print(s); fflush(stdout) }
func report(_ label: String, _ t: Any.Type) {
    let m = _mangledTypeName(t) ?? "<none>"
    say("\(label): mangled=\(m) roundtrip=\(_typeByName(m).map(String.init(describing:)) ?? "NIL")")
}
report("PlainGen<CopyablePayload>", PlainGen<CopyablePayload>.self)
report("Gen<CopyablePayload>     ", Gen<CopyablePayload>.self)
report("Gen<Int>                 ", Gen<Int>.self)
say("Gen<Pool> by name        : \(_typeByName("4mini3GenVyAA4PoolVG").map(String.init(describing:)) ?? "NIL")")
say("Pool by name             : \(_typeByName("4mini4PoolV").map(String.init(describing:)) ?? "NIL")")
