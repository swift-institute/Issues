/// Single-module reproduction of @_rawLayout deinit bug
/// Run: swift run SingleModuleTest

// MARK: - Bug: deinit skipped with generic-dependent @_rawLayout

struct Box<T, let N: Int>: ~Copyable {
    @_rawLayout(likeArrayOf: T, count: N)
    struct Raw: ~Copyable { init() {} }

    var raw: Raw
    init() { raw = Raw() }
    @inline(never) deinit { print("Box.deinit") }
}

// MARK: - Control: deinit works with fixed @_rawLayout

struct BoxFixed<T, let N: Int>: ~Copyable {
    @_rawLayout(like: Int)
    struct Raw: ~Copyable { init() {} }

    var raw: Raw
    init() { raw = Raw() }
    @inline(never) deinit { print("BoxFixed.deinit") }
}

// MARK: - Token test: adding class forces destroy path

final class Token: Sendable {
    init() {}
    deinit { print("Token.deinit") }
}

struct BoxWithToken<T, let N: Int>: ~Copyable {
    @_rawLayout(likeArrayOf: T, count: N)
    struct Raw: ~Copyable { init() {} }

    var raw: Raw
    let token: Token
    init() { raw = Raw(); token = Token() }
    @inline(never) deinit { print("BoxWithToken.deinit") }
}

// MARK: - Tests

print("=== Box<Int, 4> (BUG: expects deinit) ===")
do { var b = Box<Int, 4>(); _ = consume b }
print("=== end ===\n")

print("=== BoxFixed<Int, 4> (Control: expects deinit) ===")
do { var b = BoxFixed<Int, 4>(); _ = consume b }
print("=== end ===\n")

print("=== BoxWithToken<Int, 4> (Token forces destroy) ===")
do { var b = BoxWithToken<Int, 4>(); _ = consume b }
print("=== end ===")
