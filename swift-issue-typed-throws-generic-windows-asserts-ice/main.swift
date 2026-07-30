// Reproducer for the non-throwing -> typed-throws (nested-generic error) IRGen ICE.
// A generic struct holds a typed-throws stored closure whose error is the struct's OWN
// nested generic error `Field<Element>.Error`. Assigning a BARE non-throwing closure
// literal forces a non-throwing -> typed-throws conversion thunk whose SIL function type
// aborts IRGen on +Asserts: hasErrorResult() (SILFunctionType::getMutableErrorResult,
// AST/Types.h).
//
//   host (NoAsserts):  sh build.sh .
//   +Asserts:          docker run --rm -v "$PWD":/w -w /w swiftlang/swift:nightly-6.3-jammy sh build.sh .
public struct Field<Element> {
    public var reciprocal: (Element) throws(Field<Element>.Error) -> Element
    public enum Error: Swift.Error { case nonInvertible }
    public init(reciprocal: @escaping (Element) throws(Field<Element>.Error) -> Element) {
        self.reciprocal = reciprocal
    }
}

@inline(never)
public func make() -> Field<Bool> {
    // Bare non-throwing `{ _ in false }` into the typed-throws parameter. The dodge is to
    // spell the closure's signature explicitly: `{ (_: Bool) throws(Field<Bool>.Error) -> Bool in false }`.
    Field<Bool>(reciprocal: { _ in false })
}

_ = make()
