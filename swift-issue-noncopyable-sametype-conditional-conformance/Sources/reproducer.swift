#if canImport(Darwin)
    import func Darwin.fflush
    import var Darwin.stdout
#elseif canImport(Glibc)
    import func Glibc.fflush
    import var Glibc.stdout
#elseif canImport(ucrt)
    import func ucrt.fflush
    import func ucrt.__acrt_iob_func
    let stdout = __acrt_iob_func(1)
#endif

protocol P {}
struct Pool: ~Copyable {}
struct Gen<A: ~Copyable> {}
extension Gen: P where A == Pool {}
struct W<S: P> {
    var s: S
    var c: Int { 42 }
}
func say(_ s: String) {
    print(s)
    fflush(stdout)
}
let w = W<Gen<Pool>>(s: .init())
say("constructed")
say("c = \(w.c)")
