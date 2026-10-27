// Bug1Middleware: struct storing 2+ cross-module @_rawLayout+deinit fields
//
// THIS MODULE CRASHES the LLVM verifier under -O.
//
// The crash occurs during the LLVM "verify" pass on this module's
// compiled output. The @_rawLayout type metadata from Bug1Core is
// incorrectly lowered to LLVM IR, producing instructions that
// don't dominate their uses.
//
// THRESHOLD: 1 field = OK, 2+ fields = CRASH
//
// The fields don't even need to be @usableFromInline or accessed
// from @inlinable code. The mere presence of 2+ @_rawLayout+deinit
// fields from a cross-module generic enum is sufficient.

public import Bug1Core

public struct Buffer<Element: ~Copyable>: ~Copyable {
    var _a: Container<Element>.Inline<8>
    var _b: Container<Element>.Inline<4>

    public init() {
        self._a = Container<Element>.Inline<8>()
        self._b = Container<Element>.Inline<4>()
    }
}
