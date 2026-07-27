/// Property wrapper with phantom Tag type for extension namespacing.
public struct Property<Tag, Base: ~Copyable>: ~Copyable {
    @usableFromInline internal var _base: Base
    @inlinable public init(_ base: consuming Base) { self._base = base }
    @inlinable public var base: Base {
        _read { yield _base }
        _modify { yield &_base }
    }
}

extension Property: Copyable where Base: Copyable {}

extension Property where Base: ~Copyable {
    /// View type for ~Copyable access via pointer.
    @safe
    public struct View: ~Copyable, ~Escapable {
        @usableFromInline internal let _base: UnsafeMutablePointer<Base>

        @inlinable
        @_lifetime(borrow base)
        public init(_ base: UnsafeMutablePointer<Base>) {
            unsafe _base = base
        }

        @inlinable
        public var base: UnsafeMutablePointer<Base> { unsafe _base }
    }
}
