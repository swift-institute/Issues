// Member-type lookup does not look through an UNBOUND GENERIC typealias,
// though it does through: the unbound generic NOMINAL type the alias refers
// to (row 1), the BOUND form of the same alias (row 2), a non-generic alias
// (row 3), and a NON-generic alias to an unbound generic NOMINAL (row 5).
// The rejection is specific to a generic alias base — not to alias bases, and
// not to unbound bases, as such. This file fails `swiftc -typecheck` BY
// DESIGN (row 4) and is therefore NOT a live SwiftPM target; the two
// harnesses drive it out of process. See README.md for the full matrix,
// toolchain table, and ecosystem-decoupling note (swift-institute/.github#122).

public struct Carrier<Substrate> {}

public protocol P {}

extension Carrier {
    public typealias Member = P
}

public typealias Alias<T> = Carrier<[T]>

public typealias Bare = Carrier

// Row 1 — OK: unbound generic NOMINAL base.
extension Carrier.Member { func viaNominal() {} }

// Row 2 — OK: bound generic ALIAS base.
extension Alias<Int>.Member { func viaBoundAlias() {} }

// Row 4 — error: 'Member' is not a member type of type 'Alias'.
// THE BUG: unbound generic ALIAS base.
extension Alias.Member { func viaUnboundAlias() {} }

// Row 5 — OK: NON-generic alias to an UNBOUND GENERIC NOMINAL base.
// Sharpens the claim from "alias bases break" to "GENERIC alias bases
// break" — adjudicated on swift-institute/.github#122 (W8).
extension Bare.Member { func viaNonGenericAliasToUnboundNominal() {} }
