public struct Policy<Element> {
    public enum Error: Swift.Error { case overflow }
    var _apply: (Int) throws(Error) -> Int
    public init() { _apply = { (x: Int) throws(Error) -> Int in x } }
}
