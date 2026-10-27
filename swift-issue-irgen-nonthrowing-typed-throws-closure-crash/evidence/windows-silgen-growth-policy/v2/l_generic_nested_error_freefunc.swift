public struct Policy<Element> {
    public enum Error: Swift.Error { case overflow }
}
public func make<Element>(_ f: (Int) throws(Policy<Element>.Error) -> Int) {}
public func use<Element>(_: Element.Type) { make { (x: Int) -> Int in x } as Void }
public func use2<Element>(_: Element.Type) { make { $0 } as Void }
