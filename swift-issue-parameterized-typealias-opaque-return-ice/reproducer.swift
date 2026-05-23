// reproducer.swift
//
// Swift 6.3.2 compiler ICE: "failed to produce diagnostic for expression"
// triggered by parameterized typealias + parameterized protocol opaque return.
//
// FIXED in Swift 6.5-dev (snapshot 2026-05-12-a).
//
// To test:
//   swiftc reproducer.swift -o /tmp/repro             # Swift 6.3.2: ICE expected
//   TOOLCHAINS=swift swiftc reproducer.swift -o /tmp/repro   # Swift 6.5-dev: clean

// Match production shape: constraint protocols for the local generic parameter.
protocol Sliceable {
    associatedtype Element
}

protocol Streaming {}

// Parameterized protocol with 3 primary associated types (Input/Output/Failure pattern).
protocol P<Input, Output, Failure>
where Failure: Error {
    associatedtype Input
    associatedtype Output
    associatedtype Failure: Error
    associatedtype Body: P<Input, Output, Failure>
        where Body.Input == Input,
              Body.Output == Output,
              Body.Failure == Failure
    var body: Body { get }
}

// A generic type parameterized by a Base conforming to Sliceable.
struct Generic<Base: Sliceable> {}

// A concrete type to use as the typealias's Base.
struct Concrete: Sliceable {
    typealias Element = UInt8
}

// THE TRIGGER: parameterized typealias for a generic instantiation.
typealias Alias = Generic<Concrete>

// Also test the secondary trigger: a Base-constrained extension on Generic.
extension Generic where Base == Concrete {
    func helper() -> Int { 42 }
}

struct DemoError: Error {}

// Consumer using `var body: some P<I, Output, Error>` opaque return form,
// with a generic parameter `I` constrained to Sliceable & Streaming (like
// the production parser declarations).
struct Consumer<I: Sliceable & Streaming>: P
where I.Element == UInt8 {
    typealias Output = String
    typealias Failure = DemoError

    var body: some P<I, String, DemoError> {
        Leaf<I>()
    }
}

// Self-recursive leaf to terminate the body chain at type-check time.
struct Leaf<I: Sliceable & Streaming>: P
where I.Element == UInt8 {
    typealias Input = I
    typealias Output = String
    typealias Failure = DemoError
    typealias Body = Leaf<I>
    var body: Leaf<I> { self }
}
