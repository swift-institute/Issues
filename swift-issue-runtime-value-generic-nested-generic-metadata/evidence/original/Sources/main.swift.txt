// MARK: - Runtime metadata crash: a generic type nested in a value-generic type
//
// Purpose: Reproduce the runtime SIGSEGV inside libswiftCore's generic-metadata
//   machinery that fires whenever metadata is instantiated at run time for a
//   GENERIC type nested inside a VALUE-GENERIC (`let N: Int`) type.
//
// Hypothesis (root cause): the runtime's type decoder mis-associates the
//   parent's value-generic argument with the nested type's generic-parameter
//   slot — the value argument is fed into a position the decoder expects to
//   hold a type. The Swift 6.5-dev (main nightly) runtime says so in as many
//   words before it dies:
//
//     failed type lookup for <module>.Link<1>.Node<Swift.Int>:
//     TypeDecoder.h:788: Node kind 246 "" -
//     integer value bound to non-value generic parameter
//
//   On 6.4 there is no diagnostic — the same mis-decode reaches a null
//   dereference while the metadata cache walks the descriptor.
//
// Required ingredients, each established by an A/B (A crashes, B removes only
// that ingredient and passes):
//   (1) the PARENT is value-generic. Control: an ordinary type-generic parent
//       (`enum Link<T>`) with the same nested type PASSES.
//   (2) the NESTED type is itself generic. Control: a non-generic nested type
//       (`Link<1>.Node`) PASSES.
//   (3) the type is NESTED. Control: hoisting the value generic onto the type
//       itself (`struct Node<let N: Int, Element>`) PASSES.
//   (4) metadata is requested at RUN TIME. Under `-O` the metadata for this
//       shape is emitted statically and the crash does not fire; it fires
//       whenever anything forces a runtime lookup — `_typeName`, a generic
//       function called across a module boundary, or (in the field) Swift
//       Testing's `#expect` calling `__checkBinaryOperation<A, B>`.
//
// NOT required — each of these was removed and the crash persisted:
//   `~Copyable`, `InlineArray` storage, a self-referential generic argument,
//   a phantom-tag wrapper struct, Swift Testing, and release mode.
//
// Toolchain identity:
//   AFFECTED  Swift 6.4-dev (LLVM 885b338ea38aee1, Swift db4e13695491982)
//             `swiftlang/swift@sha256:8d614165059587ce9dcf6727a76aeff4cbf1cde41fde9a9281a43803be736224`
//             (Ubuntu 24.04 noble, +assertions), on BOTH linux/amd64
//             (x86_64-unknown-linux-gnu) and linux/arm64 (aarch64).
//   AFFECTED  Apple Swift 6.4 (swiftlang-6.4.0.27.1 clang-2100.3.27.1),
//             macOS arm64 — so the defect is NOT Linux-specific.
//   AFFECTED  Swift 6.5-dev main nightly (LLVM 6f2057ffeafd4c6,
//             Swift 83c32e02f71e4bb) — still present at head, and the only
//             configuration that prints a diagnostic before dying.
//   NOT AFFECTED  Swift 6.3.3 (swift-6.3.3-RELEASE), linux/arm64 — PASSES.
//             The defect is therefore a REGRESSION introduced after 6.3.3.
//
// Reproduction:
//   cd Experiments/value-generic-nested-generic-metadata-crash
//   rm -rf .build
//   swift run -c debug
//
// Expected: prints the qualified type name, exit 0 (what Swift 6.3.3 does).
// Actual:   SIGSEGV (exit 139), "Bad pointer dereference at 0x0000000000000000",
//           crashing thread inside libswiftCore.so:
//
//     _swift_buildDemanglingForMetadata
//     swift::nameForMetadata(...)
//     swift_getTypeName
//     _typeName(_:qualified:)
//
//   In the production shape the same root cause surfaces through whichever
//   runtime path requests the metadata first, so the visible frames differ
//   while the cause does not:
//
//     -c release, via Swift Testing:
//       swift_checkMetadataState
//       type metadata completion function for ClosedRange<>.Index   <-- wrong
//                                                                   descriptor
//       swift::GenericCacheEntry::tryInitialize(...)
//       _swift_getGenericMetadata(...)
//       __swift_instantiateCanonicalPrespecializedGenericMetadata
//       __checkBinaryOperation<A, B>(...) in libTesting.so
//
//     -c debug, via the type metadata accessor:
//       swift::checkTransitiveCompleteness(...)
//       findAnyTransitiveMetadata<...>(...)
//       swift::GenericCacheEntry::tryInitialize(...)
//       _swift_getGenericMetadata(...)
//       __swift_instantiateGenericMetadata
//
//   The `ClosedRange<>.Index` frame is diagnostic in itself: an EMPTY generic
//   argument list on an unrelated stdlib type is the mis-decoded descriptor
//   surfacing, not a real ClosedRange.
//
// Date: 2026-08-09
//
// Provenance: reduced from `swift-primitives/swift-link-primitives`, whose
//   `Link<let N: Int>` / `Link.Node<Element>` pair matches ingredients (1)–(3)
//   exactly. Its test suite crashes on every Ubuntu release leg, at a
//   different test each run — consistent with "whichever runtime metadata
//   request happens first", not with a defect in any one test. Tracked at
//   `swift-institute/Issues#105`.

enum Link<let N: Int> {}

extension Link {
    struct Node<Element> {
        var element: Element
    }
}

print(_typeName(Link<1>.Node<Int>.self))
