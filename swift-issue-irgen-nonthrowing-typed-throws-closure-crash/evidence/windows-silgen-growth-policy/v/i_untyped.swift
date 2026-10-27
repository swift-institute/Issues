public struct Box<T: ~Copyable>: ~Copyable {}
public enum Growth {}
extension Growth {
    public struct Policy<Element: ~Copyable>: Sendable {
        @usableFromInline let _apply: @Sendable (Int) throws -> Int
        @inlinable package init(apply: @escaping @Sendable (Int) throws -> Int) { self._apply = apply }
    }
}
extension Growth.Policy where Element: ~Copyable {
    public enum Error: Swift.Error, Sendable, Hashable { case overflow }
}
extension Growth.Policy where Element: ~Copyable {
    @inlinable public static var exact: Self { Self { $0 } }
}
