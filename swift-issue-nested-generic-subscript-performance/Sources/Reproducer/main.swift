// ============================================================================
// EXPERIMENT: Inline Subscript Performance — Specialization Probe
// ============================================================================
// Restores the deleted Experiments/inline-subscript-performance and extends it
// to answer eeckstein's question on swiftlang/swift#86666:
//
//   "It would be interesting if you see the slowdown even if the generic
//    type gets specialized."
//
// Adds two extra rows to the original benchmark:
//   - NestedVector with @_specialize(where Element == Int, N == 3)
//   - NestedVector with `@_specializeExtension` shape (subscript only)
//
// And emits SIL at -O so we can confirm whether the original (un-annotated)
// nested call site is being specialized or not.
// ============================================================================

import Foundation

// MARK: - Timing utilities

@inline(never)
func measure(_ iterations: Int, _ block: () -> Void) -> Double {
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
        block()
    }
    return (CFAbsoluteTimeGetCurrent() - start) / Double(iterations) * 1_000_000_000
}

// Stdlib-style blackHole — @_optimize(none) prevents the optimizer from
// seeing through the call and DCE-ing the loop body.
@inline(never)
func blackHole<T>(_ x: T) {
    @_optimize(none) func _bh<U>(_ y: U) {}
    _bh(x)
}

// Original benchmark sink — captured here for methodology comparison.
@inline(never)
func sink<T>(_ x: T) {
    withUnsafePointer(to: x) { _ in }
}

// Opaque value source — prevents the optimizer from constant-folding
// storage values into the call site, which would erase any subscript work.
@inline(never)
@_optimize(none)
func opaque(_ a: Int, _ b: Int, _ c: Int) -> InlineArray<3, Int> {
    return [a, b, c]
}

@inline(never)
@_optimize(none)
func opaqueRepeating<let N: Int>(_ x: Int) -> InlineArray<N, Int> {
    return InlineArray<N, Int>(repeating: x)
}

// MARK: - Original control: flat structs

struct FlatVector3Read {
    var _elements: InlineArray<3, Int>

    @inlinable
    subscript(index: Int) -> Int {
        _read { yield _elements[index] }
        _modify { yield &_elements[index] }
    }
}

struct FlatVector3Get {
    var _elements: InlineArray<3, Int>

    @inlinable
    subscript(index: Int) -> Int {
        get { _elements[index] }
        set { _elements[index] = newValue }
    }
}

// MARK: - Original suspect: nested generic ~Copyable

enum NestedVector<Element: ~Copyable, let N: Int>: ~Copyable {}

extension NestedVector where Element: ~Copyable {
    struct Inline: ~Copyable {
        var _elements: InlineArray<N, Element>

        @inlinable
        subscript(index: Int) -> Element {
            _read { yield _elements[index] }
            _modify { yield &_elements[index] }
        }
    }
}

extension NestedVector.Inline: Copyable where Element: Copyable {}

// MARK: - Variant A: same shape, with @_specialize on a read method

// @_specialize doesn't apply to subscripts — we wrap subscript access in a
// method so we can attach the attribute. If specialization is the missing
// piece, calling .read(at:) should be ~as fast as the flat struct.

enum NestedVectorSpec<Element: ~Copyable, let N: Int>: ~Copyable {}

extension NestedVectorSpec where Element: ~Copyable {
    struct Inline: ~Copyable {
        var _elements: InlineArray<N, Element>

        @inlinable
        subscript(index: Int) -> Element {
            _read { yield _elements[index] }
            _modify { yield &_elements[index] }
        }
    }
}

extension NestedVectorSpec.Inline where Element: Copyable {
    @inlinable
    @_specialize(exported: true, where Element == Int, N == 3)
    borrowing func read(at index: Int) -> Element {
        return self[index]
    }
}

extension NestedVectorSpec.Inline: Copyable where Element: Copyable {}

// MARK: - Variant B: same shape, force-specialized via a typealias monomorph wrapper

// A concrete struct whose body delegates to the generic nested type. If the
// problem is that callers can't see through the generic boundary, this should
// monomorphize the call site even without @_specialize.
struct NestedVectorMonoWrapper {
    var inner: NestedVector<Int, 3>.Inline

    @inlinable
    subscript(index: Int) -> Int {
        _read { yield inner[index] }
        _modify { yield &inner[index] }
    }
}

// MARK: - Benchmarks

@inline(never)
func runBenchmarks() {
    let iterations = 10_000_000

    print("═══════════════════════════════════════════════════════════════")
    print("INLINE SUBSCRIPT PERFORMANCE — SPECIALIZATION PROBE")
    print("Swift: \(swiftVersion())")
    print("═══════════════════════════════════════════════════════════════")
    print()

    // Read seed values from argv so the compiler can't see them.
    let s0 = Int(CommandLine.arguments.dropFirst().first ?? "10") ?? 10
    let s1 = Int(CommandLine.arguments.dropFirst(2).first ?? "20") ?? 20
    let s2 = Int(CommandLine.arguments.dropFirst(3).first ?? "30") ?? 30

    let rawArr     = opaque(s0, s1, s2)
    let flatRead   = FlatVector3Read(_elements: opaque(s0, s1, s2))
    let flatGet    = FlatVector3Get(_elements: opaque(s0, s1, s2))
    let nested     = NestedVector<Int, 3>.Inline(_elements: opaque(s0, s1, s2))
    let nestedSpec = NestedVectorSpec<Int, 3>.Inline(_elements: opaque(s0, s1, s2))
    let mono       = NestedVectorMonoWrapper(inner: .init(_elements: opaque(s0, s1, s2)))

    let rawNs = measure(iterations) {
        blackHole(rawArr[0] &+ rawArr[1] &+ rawArr[2])
    }
    let flatReadNs = measure(iterations) {
        blackHole(flatRead[0] &+ flatRead[1] &+ flatRead[2])
    }
    let flatGetNs = measure(iterations) {
        blackHole(flatGet[0] &+ flatGet[1] &+ flatGet[2])
    }
    let nestedNs = measure(iterations) {
        blackHole(nested[0] &+ nested[1] &+ nested[2])
    }
    let nestedSpecNs = measure(iterations) {
        blackHole(nestedSpec.read(at: 0) &+ nestedSpec.read(at: 1) &+ nestedSpec.read(at: 2))
    }
    let monoNs = measure(iterations) {
        blackHole(mono[0] &+ mono[1] &+ mono[2])
    }

    func row(_ label: String, _ ns: Double) {
        let mult = ns / rawNs
        print("\(label.padding(toLength: 38, withPad: " ", startingAt: 0))" +
              "\(String(format: "%6.1f", ns))ns  (\(String(format: "%.2f", mult))x)")
    }

    print("BLACKHOLE methodology (\(iterations) iter):")
    print("───────────────────────────────────────────────────────────────")
    row("Raw InlineArray (baseline)",     rawNs)
    row("FlatVector3 (_read accessor)",   flatReadNs)
    row("FlatVector3 (get accessor)",     flatGetNs)
    row("NestedVector.Inline",            nestedNs)
    row("NestedVectorSpec.Inline (@_spec)", nestedSpecNs)
    row("NestedVectorMonoWrapper",        monoNs)
    print()

    // Original methodology — sum accumulator + sink at end.
    print("ORIGINAL methodology (sum + sink) (\(iterations) iter):")
    print("───────────────────────────────────────────────────────────────")
    var sum = 0
    let oRawNs = measure(iterations) {
        sum &+= rawArr[0] &+ rawArr[1] &+ rawArr[2]
    }
    let oFlatReadNs = measure(iterations) {
        sum &+= flatRead[0] &+ flatRead[1] &+ flatRead[2]
    }
    let oFlatGetNs = measure(iterations) {
        sum &+= flatGet[0] &+ flatGet[1] &+ flatGet[2]
    }
    let oNestedNs = measure(iterations) {
        sum &+= nested[0] &+ nested[1] &+ nested[2]
    }
    let oNestedSpecNs = measure(iterations) {
        sum &+= nestedSpec.read(at: 0) &+ nestedSpec.read(at: 1) &+ nestedSpec.read(at: 2)
    }
    let oMonoNs = measure(iterations) {
        sum &+= mono[0] &+ mono[1] &+ mono[2]
    }
    sink(sum)

    func orow(_ label: String, _ ns: Double) {
        let mult = ns / oRawNs
        print("\(label.padding(toLength: 38, withPad: " ", startingAt: 0))" +
              "\(String(format: "%6.1f", ns))ns  (\(String(format: "%.2f", mult))x)")
    }

    orow("Raw InlineArray (baseline)",     oRawNs)
    orow("FlatVector3 (_read accessor)",   oFlatReadNs)
    orow("FlatVector3 (get accessor)",     oFlatGetNs)
    orow("NestedVector.Inline",            oNestedNs)
    orow("NestedVectorSpec.Inline (@_spec)", oNestedSpecNs)
    orow("NestedVectorMonoWrapper",        oMonoNs)
    print()
}

@inline(never)
func swiftVersion() -> String {
    #if compiler(>=6.4)
    return "6.4-dev (or newer)"
    #elseif compiler(>=6.3)
    return "6.3.x"
    #elseif compiler(>=6.2)
    return "6.2.x"
    #else
    return "<6.2"
    #endif
}

// Anchor symbols so the optimizer can't see through the call site at -O when
// emitting SIL — we want to read the SIL of the actual specialized (or not)
// subscript implementations.
@inline(never)
@_optimize(none)
func _anchor() {
    var n = NestedVector<Int, 3>.Inline(_elements: [1, 2, 3])
    _ = n[0]
    n[1] = 99

    var s = NestedVectorSpec<Int, 3>.Inline(_elements: [1, 2, 3])
    _ = s.read(at: 0)
    s[1] = 99

    var f = FlatVector3Read(_elements: [1, 2, 3])
    _ = f[0]
    f[1] = 99
}

runBenchmarks()
_anchor()
