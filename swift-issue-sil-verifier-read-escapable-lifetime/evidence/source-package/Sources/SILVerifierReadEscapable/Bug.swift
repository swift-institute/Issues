/// SIL Verifier Crash: `_read` yielding `~Escapable` value with `@_lifetime(borrow)`
///
/// The compiler crashes (signal 6) during SIL verification with "Found over consume"
/// when a `_read` coroutine yields a `~Copyable & ~Escapable` value whose initializer
/// has a `@_lifetime(borrow)` dependency on an `UnsafeMutablePointer` parameter.
///
/// The SIL verifier detects that the yielded value is consumed twice:
/// once by `mark_dependence [nonescaping]` and once by `destroy_value`.
///
/// Crash: SIL verifier assertion failure (signal 6)
///
/// Conditions required (ALL must be present):
/// 1. `~Copyable & ~Escapable` struct with `@_lifetime(borrow)` init
/// 2. `_read` coroutine accessor yielding that struct
/// 3. Protocol extension with `where Self: ~Copyable` constraint
/// 4. `-enable-experimental-feature Lifetimes`
/// 5. swift.org open-source toolchain (+assertions build)

// MARK: - Minimal Reproduction

public struct Wrapper<Base: ~Copyable>: ~Copyable, ~Escapable {
    @usableFromInline
    var _base: UnsafeMutablePointer<Base>

    @inlinable
    @_lifetime(borrow base)
    public init(_ base: UnsafeMutablePointer<Base>) {
        unsafe _base = base
    }
}

public protocol P: ~Copyable {}

extension P where Self: ~Copyable {
    public var wrapper: Wrapper<Self> {
        mutating _read {
            yield unsafe Wrapper<Self>(&self)  // CRASHES
        }
    }
}
