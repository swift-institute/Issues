/// Extension file containing `borrowing Element` closure - TRIGGER CONDITION #4
///
/// This method combined with the Sequence conformance in Container.swift
/// triggers the compiler bug during module emission.
///
/// Comment out the `withMin` method below to see the code compile successfully.

extension Container.Bounded where Element: ~Copyable {
    @inlinable
    public var count: Int { _storage.header }

    @inlinable
    public var isEmpty: Bool { _storage.header == 0 }
}

// TRIGGER: borrowing Element closure in extension file
extension Container.Bounded where Element: ~Copyable {
    @inlinable
    public func withMin<R>(_ body: (borrowing Element) -> R) -> R? {
        guard count > 0 else { return nil }
        return body(unsafe _cachedPtr[0])
    }
}
