public enum Outer<Element> {}

public protocol P {}

extension Outer {
    public struct Inner<Substrate> {
        internal var _x: Element   // error: type 'Substrate' does not conform to protocol 'P'
    }
}

extension Outer.Inner where Substrate: P {
    public typealias Element = Int
}
