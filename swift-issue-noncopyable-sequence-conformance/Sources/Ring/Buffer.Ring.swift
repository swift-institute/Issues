/// Bug: Conditional conformance to protocol with `associatedtype Element` causes
/// ~Copyable constraint to be lost on cross-module nested type's stored properties.
///
/// The compiler reports "type 'Element' does not conform to protocol 'Copyable'"
/// on the `Heap<Element>` stored property, even though `Heap` accepts `~Copyable`
/// elements and the struct is declared inside `extension Buffer where Element: ~Copyable`.
///
/// Root cause: The protocol's `associatedtype Element` collides with the generic
/// parameter `Element` inherited from `Buffer<Element: ~Copyable>`. The constraint
/// checker confuses them and applies the conditional conformance's
/// `where Element: Copyable` to the struct declaration context.
///
/// Conditions required (ALL must be present):
/// 1. Generic enum in another module (`Buffer<Element: ~Copyable>`)
/// 2. Nested struct via extension with `~Copyable` constraint
/// 3. Stored property using a class generic over `Element: ~Copyable`
/// 4. Conditional `Copyable` conformance on the nested struct
/// 5. Conformance to a protocol with `associatedtype Element` (same name as generic param)

import swift_issue_noncopyable_sequence_conformance_Core

// MARK: - Minimal Reproduction

extension Buffer where Element: ~Copyable {
    public struct Ring: ~Copyable {
        var storage: Heap<Element>  // ❌ error: type 'Element' does not conform to protocol 'Copyable'
    }
}

extension Buffer.Ring: Copyable where Element: Copyable {}
