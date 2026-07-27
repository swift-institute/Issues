/// WORKAROUND: Nested View Types
///
/// Instead of one generic Property.View with Tag discrimination via extensions,
/// use separate View types nested inside each Tag namespace.
///
/// This avoids the compiler bug while preserving the `.all` naming.

import PropertyLib
import SequenceLib

// ============================================================================
// WORKAROUND PATTERN: Nested View Types
// ============================================================================

extension Collection {
    /// Workaround: View nested inside Count namespace
    public enum Count2 {
        @safe
        public struct View<Base: Collection.`Protocol` & ~Copyable>: ~Copyable, ~Escapable {
            @usableFromInline let _base: UnsafeMutablePointer<Base>

            @inlinable @_lifetime(borrow base)
            public init(_ base: UnsafeMutablePointer<Base>) { unsafe _base = base }

            /// ✅ COMPILES: `all` on Collection.Count2.View
            @inlinable
            public var all: Int { 42 }
        }
    }

    /// Workaround: View nested inside Remove namespace
    public enum Remove2 {
        @safe
        public struct View<Base: Collection.Clearable & ~Copyable>: ~Copyable, ~Escapable {
            @usableFromInline let _base: UnsafeMutablePointer<Base>

            @inlinable @_lifetime(borrow base)
            public init(_ base: UnsafeMutablePointer<Base>) { unsafe _base = base }

            /// ✅ COMPILES: `all` on Collection.Remove2.View - different type, no conflict
            @_lifetime(&self) @inlinable
            public mutating func all() { unsafe _base.pointee.removeAll() }
        }
    }
}

// ============================================================================
// WHY THIS WORKS
// ============================================================================
//
// The buggy pattern uses ONE generic type with Tag discrimination:
//   Property.View where Tag == A  →  defines `all`
//   Property.View where Tag == B  →  defines `all`  // BUG: redeclaration
//
// The workaround uses SEPARATE types per Tag:
//   Collection.Count2.View  →  defines `all`
//   Collection.Remove2.View →  defines `all`  // OK: different type entirely
//
// Trade-off: Requires defining a View struct per Tag instead of reusing
// one generic Property.View, but preserves the desired API naming.
