// LibraryB: Calls the tuple append function from LibraryA
// This triggers a compiler crash in SILGen.

public import LibraryA

/// A simple wrapper that uses parameter packs.
public struct Parser<Output> {
    public let output: Output
    public init(_ output: Output) { self.output = output }

    @inlinable
    public func map<U>(_ transform: (Output) -> U) -> Parser<U> {
        Parser<U>(transform(output))
    }
}

/// Combines two parsers and flattens their output tuples.
///
/// This function crashes the compiler because it calls `Tuple.Append.apply`
/// from a different module, passing a pack expansion as an argument.
@inlinable
public func combine<each O1, O2>(
    _ first: Parser<(repeat each O1)>,
    _ second: Parser<O2>
) -> Parser<(repeat each O1, O2)> {
    let tuple = first.output
    let element = second.output

    // CRASHES: Cross-module call with pack expansion argument
    return Parser(Tuple.Append.apply(tuple, element))
}

// WORKAROUND: Inline the pack expansion (works, but loses abstraction)
// @inlinable
// public func combineWorkaround<each O1, O2>(
//     _ first: Parser<(repeat each O1)>,
//     _ second: Parser<O2>
// ) -> Parser<(repeat each O1, O2)> {
//     let tuple = first.output
//     let element = second.output
//     return Parser((repeat each tuple, element))  // ✅ Works
// }
