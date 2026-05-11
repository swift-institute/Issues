/// Linux Release-Mode Pointer Arithmetic Miscompile
///
/// Minimal reproducer: `UnsafeMutablePointer<Int>.advanced(by:)` wrapped in a
/// user-authored `-` operator overload is miscompiled on Linux release builds.
/// A `.pointee` read following the operator returns the wrong value — wrong
/// load address, not wrong arithmetic.
///
/// Failure shape:
///   let backed = advanced - Vec(2); #expect(backed.pointee == 20)  // FAILS on Linux release
///
/// Affected toolchains:
///   • Swift 6.3 stable Linux release    — FAILS
///   • Swift 6.4-dev nightly Linux release — FAILS
///
/// Unaffected toolchains:
///   • macOS (all builds)                 — PASSES
///   • Windows                            — PASSES
///   • Linux debug builds                 — PASSES
///
/// Heisenbug character: any diagnostic instrumentation between the operator
/// call and the `.pointee` read (intermediate let-bindings, `UInt(bitPattern:)`
/// materialization, print statements) masks the failure.
///
/// What was stripped from the original failing form (none load-bearing):
///   • `Tagged<Pointee, Ordinal>` wrapper
///   • Custom signed-integer Vector
///   • `Carrier.Protocol`
///   • `~Copyable` generic parameter
///   • All package operator overloads
///
/// What remains is the minimum trigger: stdlib `UnsafeMutablePointer<Int>` +
/// 10-line `Vec` struct + user-authored `+` / `-` operators wrapping
/// `.advanced(by:)`.

public struct Vec {
    public let raw: Int
    public init(_ r: Int) { self.raw = r }
}

public func + (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    unsafe lhs.advanced(by: rhs.raw)
}

public func - (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    unsafe lhs.advanced(by: -rhs.raw)
}
