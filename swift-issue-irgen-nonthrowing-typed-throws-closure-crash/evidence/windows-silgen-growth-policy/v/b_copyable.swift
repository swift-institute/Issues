public struct Box<T> {}
public enum Growth {}
extension Growth {
    public struct Policy<Element>: Sendable {
        @usableFromInline let _apply: @Sendable (Int) throws(Error) -> Int
        @inlinable package init(apply: @escaping @Sendable (Int) throws(Error) -> Int) { self._apply = apply }
    }
}
extension Growth.Policy {
    public enum Error: Swift.Error, Sendable, Hashable { case overflow }
}
extension Growth.Policy {
    @inlinable public static var exact: Self { Self { $0 } }
}
