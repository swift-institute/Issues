/// IRGen Crash: Async Function with Typed Throws and Nested Error Type Under Generic
///
/// The compiler crashes (signal 11) during IR generation when ALL THREE conditions are met:
/// 1. Generic type (any generic parameter)
/// 2. Nested error type under that generic
/// 3. Async function with typed throws using the nested error
///
/// Note: ~Copyable is NOT required - any generic triggers this.

// MARK: - Minimal Reproduction (4 lines)

public enum Box<T> {
    public enum Error: Swift.Error { case fail }
    public static func go() async throws(Error) {}  // CRASHES
}

// MARK: - Verified Working Cases

// ✅ WORKS: Sync function (no async)
public enum SyncBox<T> {
    public enum Error: Swift.Error { case fail }
    public static func go() throws(Error) {}
}

// ✅ WORKS: Untyped throws
public enum UntypedBox<T> {
    public enum Error: Swift.Error { case fail }
    public static func go() async throws {}
}

// ✅ WORKS: Non-generic container
public enum NonGenericBox {
    public enum Error: Swift.Error { case fail }
    public static func go() async throws(Error) {}
}

// ✅ WORKS: Top-level error type
public enum TopError: Swift.Error { case fail }
public enum TopErrorBox<T> {
    public static func go() async throws(TopError) {}
}

// ✅ WORKS: Nested return type is fine (only error triggers crash)
public enum NestedReturnBox<T> {
    public struct Result { let value: Int }
    public static func go() async throws(TopError) -> Result { Result(value: 0) }
}

// ✅ WORKS: Typealias to hoisted type
public enum HoistedError: Swift.Error { case fail }
public enum TypealiasBox<T> {
    public typealias Error = HoistedError
    public static func go() async throws(Error) {}
}

// MARK: - Also crashes with ~Copyable (but ~Copyable is not the cause)

public enum CopyableBox<T: ~Copyable> {
    public enum Error: Swift.Error { case fail }
    public static func go() async throws(Error) {}  // CRASHES (same bug)
}
