// Minimal standalone reproducer — Swift compiler crash (ICE).
//
//   swiftc -O reproducer.swift -c -o /tmp/x.o
//
// Crashes swift-frontend with signal 6:
//
//   Assertion failed: (!type.hasTypeParameter()), function SILArgument
//   at SILArgument.cpp:40.
//   4. While running pass #N SILFunctionTransform "FunctionSignatureOpts"
//      on SILFunction "@$s...5parseys5UInt8VxAA7MyErrorOyxGYKlF".
//   9. swift::FunctionSignatureTransform::createFunctionSignatureOptimizedFunction()
//
// TRIGGER (each ingredient verified necessary — remove one and it compiles clean):
//   1. a GENERIC function (`<T>`),
//   2. typed throws whose error type carries the function's OWN abstract type
//      parameter — `throws(MyError<T>)` (a NON-generic error, or a CONCRETE
//      instantiation like `MyError<Int>`, compiles clean),
//   3. at least one same-module CALLER of the generic function (no caller → clean),
//   4. optimization: `-O` (FunctionSignatureOpts only runs at -O; debug is clean).
//
// NOT required: any protocol conformance, a struct/nesting, `inout`, `Sendable`,
// `@inline(never)`, `-enable-testing`, `-parse-as-library`, `-enable-default-cmo`,
// or any experimental/upcoming feature (SuppressedAssociatedTypes, Lifetimes, …).
//
// TOOLCHAINS (each verified by running the reducer; `swift --version`-confirmed):
//   Swift 6.2, 6.2.3 ................................. CRASH (SIL verifier; asserts off)
//   Swift 6.3.1, 6.3.2 (current Xcode default) ....... CRASH (ASSERT !type.hasTypeParameter())
//   6.3-dev (2026-01-07/01-09/02-05) ................. CRASH
//   6.4-dev (2026-03-16-a, 2026-05-07-a) ............. CRASH
//   6.5-dev (2026-05-12-a, swift-latest) ............. CRASH
//   => present on every tested toolchain 6.2 → 6.5-dev; NOT a 6.3 regression
//      (6.3 only added the earlier SILArgument assert); NOT fixed on the latest 6.5-dev.

public enum MyError<T>: Swift.Error { case fail }

public func parse<T>(_ x: T) throws(MyError<T>) -> UInt8 { throw .fail }

public func run<T>(_ x: T) -> UInt8 {
    do { return try parse(x) } catch { return 0 }
}
