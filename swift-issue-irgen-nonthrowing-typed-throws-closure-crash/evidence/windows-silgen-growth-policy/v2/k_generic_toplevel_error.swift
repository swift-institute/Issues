public enum E: Swift.Error { case overflow }
public struct Policy<Element> {
    let _apply: (Int) throws(E) -> Int
    init(apply: @escaping (Int) throws(E) -> Int) { self._apply = apply }
    public static var exact: Policy { Policy { $0 } }
}
