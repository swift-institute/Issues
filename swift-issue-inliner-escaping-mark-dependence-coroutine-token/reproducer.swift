// Minimal reproducer — EarlyPerfInliner aborts on an ESCAPING mark_dependence
// attached to a begin_apply (coroutine) token result.
//
//   swiftc -O -swift-version 6 \
//     -enable-experimental-feature Lifetimes \
//     -enable-experimental-feature SuppressedAssociatedTypes \
//     reproducer.swift -c -o /tmp/x.o
//
// Expected: exit 0. Observed on Swift 6.5-dev: signal 6,
//   Assertion `mdi.isNonEscaping()' failed. (SILInliner.cpp:167)
//
// CLEAN on 6.3.3-RELEASE / 6.4.x-dev / main 2026-05-27 — see ../README.md matrix.

public protocol P<U>: ~Copyable, ~Escapable {
    associatedtype U: ~Copyable & ~Escapable
    var u: U { @_lifetime(borrow self) borrowing get }
    @_lifetime(copy u) init(_ u: consuming U)
}
public struct T<U: ~Copyable & ~Escapable>: ~Copyable, ~Escapable {
    public var u: U
    @_lifetime(copy u) public init(_ u: consuming U) { self.u = u }
}
extension T: Copyable where U: Copyable & ~Escapable {}
extension T: Escapable where U: Escapable & ~Copyable {}
extension T: P where U: ~Copyable & ~Escapable {}
public struct A {
    @inlinable public func f<C: P>(_ v: C) -> C where C.U: FixedWidthInteger { C(v.u &+ 1) }
}
@inlinable public func go(_ x: T<Int64>, _ a: A) -> T<Int64> { a.f(x) }
