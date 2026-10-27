public struct Policy<Element> {
    public enum Error: Swift.Error { case overflow }
    let _apply: (Int) throws(Error) -> Int
    init(apply: @escaping (Int) throws(Error) -> Int) { self._apply = apply }
    public static var exact: Policy { Policy(apply: { $0 }) }
}
