// Standalone reducer for the File.System.Write.Streaming.write(chunk:to:)
// SIL ownership-verifier crash ("Found outside of lifetime use?!").
//
// Mirrors the production shape in
//   swift-file-system/Sources/File System Core/File.System.Write.Streaming+API.swift:264
//
//   public static func write(chunk span: borrowing Span<Byte>,
//                            to context: borrowing Context) throws(Error) {
//       do { try writeAll(span, to: context.descriptor!) }
//       catch { throw Error(error) }
//   }
//
// Ingredients reproduced here:
//   1. `~Copyable` Context struct (Sendable) holding an Optional `~Copyable`
//      owning field (Descriptor with a closing deinit).
//   2. A static func taking `borrowing Span<UInt8>` + `borrowing Context`.
//   3. `do { try callee(span, to: context.field!) } catch { throw Outer(inner) }`
//      — typed-throws error MAPPING from an Inner error to an Outer error,
//      generating a `try_apply` with normal+error continuation blocks.
//   4. The throwing callee takes `@guaranteed Span<UInt8>` + `@guaranteed Descriptor`.
//
// Build:  swiftc -O repro.swift -o /tmp/repro_o
//         swiftc -Xfrontend -sil-verify-all repro.swift -o /tmp/repro_verify

enum InnerError: Error { case io(String) }
enum OuterError: Error {
    case wrapped
    init(_ e: InnerError) { self = .wrapped }
}

struct Descriptor: ~Copyable, Sendable {
    var raw: Int32
    init(raw: Int32) { self.raw = raw }
    deinit { /* closes fd */ }
}

struct Context: ~Copyable, Sendable {
    var descriptor: Descriptor?
    let isAtomic: Bool
    init(descriptor: consuming Descriptor, isAtomic: Bool) {
        self.descriptor = consume descriptor
        self.isAtomic = isAtomic
    }
}

@inline(never)
func writeAll(_ span: borrowing Span<UInt8>, to descriptor: borrowing Descriptor) throws(InnerError) {
    if descriptor.raw < 0 { throw InnerError.io("bad fd") }
    if span.count == 0 { throw InnerError.io("empty") }
}

@_optimize(none)
func write(chunk span: borrowing Span<UInt8>, to context: borrowing Context) throws(OuterError) {
    do {
        try writeAll(span, to: context.descriptor!)
    } catch {
        throw OuterError(error)
    }
}

// Force optimization to actually exercise the write path (top-level code).
let storage: [UInt8] = [1, 2, 3, 4]
storage.withUnsafeBufferPointer { buf in
    let span = Span(_unsafeElements: buf)
    let ctx = Context(descriptor: Descriptor(raw: 1), isAtomic: false)
    do {
        try write(chunk: span, to: ctx)
        print("ok")
    } catch {
        print("err")
    }
}
