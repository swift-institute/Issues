public struct Target: ~Copyable {
    public init() {}
}

public struct View<Base: ~Copyable>: ~Copyable, ~Escapable {
    @_lifetime(borrow base)
    public init(_ base: borrowing Base) {}
}
