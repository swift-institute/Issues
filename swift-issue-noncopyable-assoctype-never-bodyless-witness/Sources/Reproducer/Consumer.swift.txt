// repro-consumer.swift  —  module "N" (models Serializer_Trace_Primitives)
//
// See repro-core.swift for the build sequence. Compiling THIS file (the consumer
// module that conforms a second type with Body == Never) is what crashes: the
// consumer's witness table references M's default `body.read`, which is emitted
// here as a bodyless `shared [serialized]` SIL function.

public import M

// A Body == Never conformer in a CONSUMER module. (Models Serializer.Trace, and
// equally Serializer.Map / .Optional / .Filter / … — every leaf combinator.)
public struct Use: P {
    public typealias Body = Never
    public init() {}
}
