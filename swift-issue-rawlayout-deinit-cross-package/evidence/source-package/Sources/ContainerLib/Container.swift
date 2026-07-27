/// @_rawLayout Deinit Bug: likeArrayOf with generic parameters
///
/// Bug: deinit not called when @_rawLayout uses generic parameters from outer type.
///
/// Condition: `@_rawLayout(likeArrayOf: T, count: N)` where T and N are generics.
///
/// Note: `@_rawLayout(like: Int)` works correctly.

// MARK: - Minimal Reproduction

public struct Box<T, let N: Int>: ~Copyable {
    @_rawLayout(likeArrayOf: T, count: N)
    struct Raw: ~Copyable { init() {} }

    var raw: Raw
    public init() { raw = Raw() }
    @inline(never) deinit { print("Box.deinit") }  // BUG: Never called
}

// MARK: - Control: Works with @_rawLayout(like: Int)

public struct BoxFixed<T, let N: Int>: ~Copyable {
    @_rawLayout(like: Int)  // Fixed type, not using generics
    struct Raw: ~Copyable { init() {} }

    var raw: Raw
    public init() { raw = Raw() }
    @inline(never) deinit { print("BoxFixed.deinit") }  // WORKS
}

// MARK: - Workaround Test: Top-level @_rawLayout (not nested)

@_rawLayout(likeArrayOf: T, count: N)
public struct RawBoxStorage<T, let N: Int>: ~Copyable { public init() {} }

public struct BoxTopLevel<T, let N: Int>: ~Copyable {
    var raw: RawBoxStorage<T, N>
    public init() { raw = .init() }
    @inline(never) deinit { print("BoxTopLevel.deinit") }
}

// MARK: - Token Test: Is outer destruction skipped entirely?

public final class Token: Sendable {
    public init() {}
    deinit { print("Token.deinit") }
}

public struct BoxWithToken<T, let N: Int>: ~Copyable {
    @_rawLayout(likeArrayOf: T, count: N)
    struct Raw: ~Copyable { init() {} }

    var raw: Raw
    public let token: Token
    public init() { raw = Raw(); token = Token() }
    @inline(never) deinit { print("BoxWithToken.deinit") }
}
