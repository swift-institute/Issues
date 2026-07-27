// MINIMAL REPRODUCTION: SILGen crash with property wrapper + ~Copyable cross-module
//
// Conditions (all required):
// 1. Property wrapper on a ~Copyable type
// 2. Cross-module usage (type in Lib, used in Tests)
//
// NOT required: @inlinable, @frozen, @usableFromInline, Sendable

@propertyWrapper
public struct Wrapper<Value: ~Copyable>: ~Copyable {
    private var _value: Value

    public init(wrappedValue: consuming Value) {
        self._value = wrappedValue
    }

    public var wrappedValue: Value {
        _read { yield _value }
        _modify { yield &_value }
    }
}

public struct Box<Value: ~Copyable>: ~Copyable {
    @Wrapper public var value: Value

    public init(_ value: consuming Value) {
        self.value = value
    }
}
