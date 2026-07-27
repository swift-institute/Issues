public import PropertyLib

public enum Sequence {
    public protocol `Protocol`: ~Copyable {
        associatedtype Element
        associatedtype Iterator: IteratorProtocol where Iterator.Element == Element
        borrowing func makeIterator() -> Iterator
    }
    public enum Count {}
}

/// Extension with Tag == Sequence.Count
extension Property.View where Tag == Sequence.Count, Base: Sequence.`Protocol` & ~Copyable {
    @inlinable
    public var all: Int {
        var count = 0
        var iterator = unsafe base.pointee.makeIterator()
        while iterator.next() != nil { count += 1 }
        return count
    }
}
