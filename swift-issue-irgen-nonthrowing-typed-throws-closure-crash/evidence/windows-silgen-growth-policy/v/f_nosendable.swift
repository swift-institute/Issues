public struct Box<T: ~Copyable>: ~Copyable {}
public enum Growth {}
extension Growth {
    public struct Policy<Element: ~Copyable> {
        @usableFromInline let _apply: (Int) throws(Error) -> Int
        @inlinable package init(apply: @escaping (Int) throws(Error) -> Int) { self._apply = apply }
    }
}
extension Growth.Policy where Element: ~Copyable {
    public enum Error: Swift.Error, Hashable { case overflow }
}
extension Growth.Policy where Element: ~Copyable {
    @inlinable public static var exact: Self { Self { $0 } }
}
