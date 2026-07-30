// Embedded/Wasm `MandatoryPerformanceOptimizations` SIL crash — host stub.
//
// The trigger (`Crash.swift.txt`, two live lines) requires the production
// `swift-index-primitives` dependency chain AND the wasm32 Embedded Swift SDK
// on a 6.3.x toolchain — a configuration that cannot run in this repository's
// default local test lane (the Issues package is dependency-free by
// convention, and the crash is a SwiftPM cross-module Embedded build). This
// executable therefore compiles on host as a stub: it prints the documented
// reproduction and exits 2 (inconclusive). It never claims a probe result.
//
// Exit code:
//   2 — always: the reproduction requires the documented Docker + wasm-SDK
//       lane; see the README for the exact verified invocation.

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation

FileHandle.standardError.write(Data(
    """
    inconclusive: this defect requires the swift-6.3.x wasm-embedded SDK and
    the production swift-index-primitives dependency chain; it cannot be
    probed from this dependency-free host target. Reproduce with the exact
    container invocation documented in this entry's README
    (docker swift:6.3.2-jammy + swift-6.3.2-RELEASE_wasm-embedded SDK,
    swift build --swift-sdk swift-6.3.2-RELEASE_wasm-embedded).

    """.utf8
))
exit(2)
#else
exit(2)
#endif
