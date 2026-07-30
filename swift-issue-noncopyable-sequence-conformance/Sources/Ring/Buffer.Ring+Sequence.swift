/// This file triggers the bug. Removing it makes the package compile.
///
/// The bug is a name collision: the protocol's `associatedtype Element` and
/// the conforming type's generic parameter `Element` (inherited from
/// `Buffer<Element>`) are confused by the constraint checker. The conditional
/// conformance's `where Element: Copyable` is incorrectly applied to the
/// struct's stored properties.
///
/// This is why `Swift.Sequence` triggers the bug — it has `associatedtype Element`.
/// Protocols without an `Element` associated type (e.g. Equatable, Hashable,
/// CustomStringConvertible) do NOT trigger it.

import swift_issue_noncopyable_sequence_conformance_Core

// MARK: - Minimal Trigger (3 lines)

protocol P {
    associatedtype Element
}

extension Buffer.Ring: P where Element: Copyable {}

// MARK: - Verified: Different associated type name does NOT trigger

// protocol Q {
//     associatedtype Value  // ← NOT "Element"
// }
// extension Buffer.Ring: Q where Element: Copyable {
//     typealias Value = Element
// }
// ✅ Compiles — no name collision
