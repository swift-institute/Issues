/// Bug: Property.View extensions with different Tag constraints report redeclaration.
///
/// Conditions Required (ALL must be present):
/// 1. Generic struct with phantom Tag parameter (Property.View)
/// 2. Protocol hierarchy (Collection.Protocol : Sequence.Protocol)
/// 3. Base constraint with ADDITIONAL refinement (Clearable : Protocol)
/// 4. Extensions constrained on different Tag types
/// 5. Same member name ('all')
///
/// Note: Bug is NOT specific to ~Escapable - also occurs with ~Copyable only.

public import PropertyLib
public import SequenceLib

public enum Collection {
    public protocol `Protocol`: SequenceLib.Sequence.`Protocol` & ~Copyable {}
    public protocol Clearable: `Protocol` & ~Copyable { mutating func removeAll() }
    public enum Count {}
    public enum Remove {}
}

// ============================================================================
// BUG: Uncomment to see the compiler error
// ============================================================================
//
// extension Property.View where Tag == Collection.Count, Base: Collection.`Protocol` & ~Copyable {
//     public var all: Int { 42 }  // note: 'all' previously declared here
// }
//
// extension Property.View where Tag == Collection.Remove, Base: Collection.Clearable & ~Copyable {
//     @_lifetime(&self)
//     public mutating func all() {}  // error: invalid redeclaration of 'all()'
// }
//
// ============================================================================
// See Workaround.swift for the working pattern
// ============================================================================
