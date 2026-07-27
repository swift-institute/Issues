/// Suboptimal Codegen: Nested Generic Type with ~Copyable Constraint
///
/// Subscript access on a nested generic type with ~Copyable constraint generates
/// code that is ~1.6x slower than an equivalent flat struct with identical implementation.
///
/// Performance issue: Nested type under generic enum with ~Copyable generates
/// suboptimal code compared to flat struct.
///
/// Conditions required (ALL must be present):
/// 1. Nested type inside generic enum: `Outer<Element, N>.Inner`
/// 2. ~Copyable suppression: `where Element: ~Copyable`
/// 3. Value generic parameter: `let N: Int`
///
/// Note: The `_read` accessor is NOT the cause. A flat struct with identical
/// `_read { yield _elements[index] }` has only 8% overhead vs 60% for nested type.

// MARK: - Slow: Nested Generic Type with ~Copyable (60% overhead)

public enum NestedVector<Element: ~Copyable, let N: Int>: ~Copyable {}

extension NestedVector where Element: ~Copyable {
    public struct Inline: ~Copyable {
        @usableFromInline
        var _elements: InlineArray<N, Element>

        @inlinable
        public init(_ elements: consuming InlineArray<N, Element>) {
            self._elements = elements
        }

        @inlinable
        public subscript(index: Int) -> Element {
            _read { yield _elements[index] }
            _modify { yield &_elements[index] }
        }
    }
}

extension NestedVector.Inline: Copyable where Element: Copyable {}

// MARK: - Fast: Flat Struct with Identical Implementation (8% overhead)

public struct FlatVector3 {
    @usableFromInline
    var _elements: InlineArray<3, Int>

    @inlinable
    public init(_ elements: consuming InlineArray<3, Int>) {
        self._elements = elements
    }

    @inlinable
    public subscript(index: Int) -> Int {
        _read { yield _elements[index] }
        _modify { yield &_elements[index] }
    }
}

// MARK: - Benchmark Results (from swift-vector-primitives experiment)
//
// Raw InlineArray:                97.4ns  (baseline)
// FlatVector3 (_read accessor):  105.0ns  (1.08x) ← Acceptable overhead
// NestedVector.Inline:           155.8ns  (1.60x) ← Unexpected overhead
//
// The only difference between FlatVector3 and NestedVector.Inline is the
// type structure. The subscript implementation is identical.
//
// Expected: Both should have ~1.08x overhead
// Actual: Nested type has 1.60x overhead (60% vs 8%)
