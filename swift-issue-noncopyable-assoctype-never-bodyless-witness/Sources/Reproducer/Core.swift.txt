// repro-core.swift  —  module "M" (models Serializer_Primitive)
//
// Minimal reproducer (1 of 2) for the bodyless-default-witness SIL crash.
// Build sequence (stock Xcode Swift 6.3.2, no special toolchain needed):
//
//   swiftc -enable-experimental-feature SuppressedAssociatedTypes \
//          -wmo -parse-as-library -emit-module \
//          -emit-module-path M.swiftmodule -module-name M repro-core.swift
//
//   swiftc -enable-experimental-feature SuppressedAssociatedTypes \
//          -Xfrontend -sil-verify-all \
//          -wmo -parse-as-library -c repro-consumer.swift -I . -module-name N
//
// The second command crashes:
//   <unknown>:0: note: Must have a construct to emit for
//   While verifying SIL function "...P...body...read" for read for body (in module 'M')
//
// On a +Asserts toolchain (e.g. the Windows 6.3.2-RELEASE toolchain, or any
// DEVELOPMENT-SNAPSHOT with assertions) the -sil-verify-all flag is not needed —
// SIL verification runs by default. On an Embedded build it is likewise not needed.
// On a NoAsserts RELEASE toolchain (stock macOS/Linux) the malformed SIL is emitted
// but never verified, so the build silently succeeds — the bug is latent there.

public protocol P: ~Copyable {
    associatedtype Body: ~Copyable          // <-- `Body: ~Copyable` is load-bearing
    var body: Body { borrowing get }
}

// Default witness for the leaf case Body == Never. Its `read` accessor yields the
// uninhabited `Never`. When this default is referenced from a *consumer* module's
// witness table it is emitted there as a `shared [serialized]` SIL function — and
// that emitted copy has no body, which the SIL verifier rejects.
extension P where Self: ~Copyable, Body == Never {
    @inlinable                              // NOT required (non-@inlinable also crashes)
    public var body: Never {
        borrowing get {                     // plain `get` also crashes
            fatalError()
        }
    }
}

// A Body == Never conformer DECLARED IN THIS (defining) module. Required: it forces
// the generic default `body.read` to be instantiated/serialized into M.swiftmodule.
// (Models Serializer.Witness, which conforms in Serializer_Primitive itself.)
public struct InCore: P {
    public typealias Body = Never
    public init() {}
}
