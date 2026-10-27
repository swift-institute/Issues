public enum Growth {}
extension Growth {
    public struct Policy<Element: ~Copyable>: Sendable {
        public enum Error: Swift.Error, Sendable, Hashable { case overflow }
        @usableFromInline let _apply: @Sendable (Int) throws(Error) -> Int
        @inlinable package init(apply: @escaping @Sendable (Int) throws(Error) -> Int) { self._apply = apply }
    }
}
extension Growth.Policy where Element: ~Copyable {
    @inlinable public static var exact: Self { Self { $0 } }
}
