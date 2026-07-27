// LibraryA: Defines a tuple append function using parameter packs

/// Non-generic namespace for tuple operations.
public enum Tuple {
    /// Append operations using parameter packs.
    public enum Append {}
}

extension Tuple.Append {
    /// Append an element to a tuple using parameter packs.
    ///
    /// This function works correctly within the same module,
    /// but crashes the compiler when called from another module.
    @inlinable
    public static func apply<each T, U>(
        _ tuple: (repeat each T),
        _ element: U
    ) -> (repeat each T, U) {
        (repeat each tuple, element)
    }
}
