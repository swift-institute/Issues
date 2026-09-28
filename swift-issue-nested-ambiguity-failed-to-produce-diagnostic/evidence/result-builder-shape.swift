// The shape the crash was found in (swift-sql `Values { "Hello"; "Goodbye" }`
// passed to an overloaded snapshot strategy), reduced to plain protocols.
// `xcrun swiftc -typecheck result-builder-shape.swift`
// → error: failed to produce diagnostic for expression
// Here `Values<String> { … }` does NOT help: a one-element pack still matches
// `Value == String`, so the builder stays ambiguous. In the real package the
// pack overload has extra constraints, and the annotation does compile.

protocol Expression { associatedtype Value }
extension String: Expression { typealias Value = String }

struct Rows<Value> {}

@resultBuilder
enum Builder<Value> {
    static func buildBlock(_ rows: Rows<Value>...) -> Rows<Value> { Rows() }
    static func buildExpression<V: Expression>(_ expression: V) -> Rows<Value>
    where Value == V.Value { Rows() }
    static func buildExpression<each V: Expression>(_ expression: (repeat each V)) -> Rows<Value>
    where Value == (repeat (each V).Value) { Rows() }
}

protocol P {}
protocol Q {}
struct Values<Value>: P, Q {
    init(@Builder<Value> _ build: () -> Rows<Value>) {}
}

func check(_ value: some P) {}
func check(_ value: some Q) {}

check(Values { "Hello"; "Goodbye" })
