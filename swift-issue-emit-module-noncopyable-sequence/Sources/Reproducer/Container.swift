/// Emit-Module Crash: ~Copyable Constraint Propagation Failure with Sequence Conformance
///
/// The compiler fails during module emission (`-emit-module`) when a generic type with
/// compound constraint (`~Copyable & Protocol`) has a nested type containing
/// `UnsafeMutablePointer<Element>`, combined with conditional `Sequence` conformance
/// and `borrowing Element` closures in extension files.
///
/// Error: "type 'Element' does not conform to protocol 'Copyable'"
///
/// Conditions required (ALL must be present):
/// 1. Compound generic constraint: `Element: ~Copyable & Protocol`
/// 2. Nested type with `UnsafeMutablePointer<Element>` stored property
/// 3. Conditional Sequence conformance: `extension Type: Sequence where Element: Copyable`
/// 4. Extension FILE with `(borrowing Element)` closure parameter
/// 5. Library target (uses `-emit-module`)
/// 6. `-enable-experimental-feature Lifetimes` flag
///
/// Note: Single constraint (`Element: ~Copyable`) does NOT trigger this bug.
///       Custom protocol conformances do NOT trigger this bug - only `Sequence`.

// MARK: - Minimal Reproduction (60 lines)

public protocol Ordering: ~Copyable {
    static func isLessThan(_ lhs: borrowing Self, _ rhs: borrowing Self) -> Bool
}

extension Ordering where Self: Comparable {
    public static func isLessThan(_ lhs: borrowing Self, _ rhs: borrowing Self) -> Bool {
        lhs < rhs
    }
}

extension Int: Ordering {}

@safe
public struct Container<Element: ~Copyable & Ordering>: ~Copyable {

    @usableFromInline
    final class Storage: ManagedBuffer<Int, Element> {
        @usableFromInline
        static func create() -> Storage {
            let storage = Storage.create(minimumCapacity: 4) { _ in 0 }
            return unsafe unsafeDowncast(storage, to: Storage.self)
        }

        @usableFromInline
        var _elementsPointer: UnsafeMutablePointer<Element> {
            unsafe withUnsafeMutablePointerToElements { unsafe $0 }
        }

        @usableFromInline
        func _readElement(at index: Int) -> Element where Element: Copyable {
            unsafe withUnsafeMutablePointerToElements { elements in
                unsafe elements[index]
            }
        }
    }

    @usableFromInline
    var _storage: Storage

    @usableFromInline
    var _cachedPtr: UnsafeMutablePointer<Element>

    public init() {
        self._storage = Storage.create()
        unsafe (self._cachedPtr = _storage._elementsPointer)
    }

    @safe
    public struct Bounded: ~Copyable {
        @usableFromInline
        var _storage: Storage

        // ERROR APPEARS HERE during module emission:
        // "type 'Element' does not conform to protocol 'Copyable'"
        @usableFromInline
        var _cachedPtr: UnsafeMutablePointer<Element>

        public let capacity: Int

        @inlinable
        public init(capacity: Int) {
            self._storage = Storage.create()
            unsafe (self._cachedPtr = _storage._elementsPointer)
            self.capacity = capacity
        }
    }
}

extension Container: Copyable where Element: Copyable {}
extension Container.Bounded: Copyable where Element: Copyable {}

// MARK: - Sequence Conformance (TRIGGER)

extension Container.Bounded: Sequence where Element: Copyable {
    public func makeIterator() -> AnyIterator<Element> {
        var index = 0
        let storage = _storage
        return AnyIterator {
            guard index < storage.header else { return nil }
            defer { index += 1 }
            return storage._readElement(at: index)
        }
    }
}

// MARK: - Verified Working Cases

// ✅ WORKS: Single constraint (no compound)
public struct SingleConstraint<Element: ~Copyable>: ~Copyable {
    public struct Bounded: ~Copyable {
        var _ptr: UnsafeMutablePointer<Element>
    }
}
// extension SingleConstraint.Bounded: Sequence where Element: Copyable { ... } // Would work

// ✅ WORKS: Custom protocol conformance (not Sequence)
protocol TestProtocol { func test() -> Int }
extension Container.Bounded: TestProtocol where Element: Copyable {
    public func test() -> Int { _storage.header }
}

// ✅ WORKS: Parse-only compilation (no module emission)
// swiftc -parse *.swift → SUCCESS
