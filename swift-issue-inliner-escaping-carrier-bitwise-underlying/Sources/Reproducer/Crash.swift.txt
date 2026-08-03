// Reduced from Carrier.Protocol's `underlying` `borrowing get` coroutine
// (swift-carrier-primitives/Sources/Carrier Protocol/_CarrierProtocol.swift)
// inlined through the generic bitwise `&(_:_:)` operator
// (swift-carrier-primitives/Sources/Carrier Primitives Standard Library
// Integration/Carrier+Bitwise.swift) as witnessed by Byte's Carrier.Protocol
// conformance (swift-byte-primitives/Sources/Byte Protocol Primitives/
// Byte+Carrier.swift) — the exact dependency edge swift-binary-parser-primitives
// pulls in transitively for its parse-primitive byte handling.
//
// Same assertion, same file/line, same pass as
// ../swift-issue-inliner-escaping-mark-dependence-coroutine-token — this is a
// second trigger of that root cause, not a new bug. See that entry's README
// for the full mechanism (EarlyPerfInliner deletes a token `mark_dependence`
// on the assumption it is always non-escaping; a generic caller that
// constructs-and-returns a value from the yielded `underlying` produces an
// escaping one instead).
public protocol Carrying<Underlying>: ~Copyable, ~Escapable {
    associatedtype Underlying: ~Copyable & ~Escapable
    var underlying: Underlying {
        @_lifetime(borrow self)
        borrowing get
    }
    @_lifetime(copy underlying)
    init(_ underlying: consuming Underlying)
}

public struct Byte: Carrying {
    public typealias Underlying = UInt8
    public let underlying: UInt8
    public init(_ underlying: consuming UInt8) { self.underlying = underlying }
}

@_disfavoredOverload
@inlinable
public func & <C: Carrying>(lhs: C, rhs: C) -> C
where C.Underlying: FixedWidthInteger {
    C(lhs.underlying & rhs.underlying)
}

@inlinable
public func maskedByte(_ a: Byte, _ b: Byte) -> Byte { a & b }
