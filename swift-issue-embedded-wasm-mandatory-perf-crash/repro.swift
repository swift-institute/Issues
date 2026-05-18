// Maximally-reduced empirical reproducer (standalone package).
//
// Triggers Swift 6.3.2 RELEASE Wasm SDK Embedded `MandatoryPerformanceOptimizations`
// SIL crash with just `swift-index-primitives` as a dep — does NOT require
// `swift-vector-primitives` (the originating package). Two lines of consumer code.
//
// VERIFIED via Docker `swift:6.3.2-jammy` + `swift-6.3.2-RELEASE_wasm-embedded` SDK:
//
//   docker run --name r -d -v $PWD:/work -w /work swift:6.3.2-jammy sleep infinity
//   docker exec r swift sdk install \
//     "https://download.swift.org/swift-6.3.2-release/wasm-sdk/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE_wasm.artifactbundle.tar.gz" \
//     --checksum "a61f0584c93283589f8b2f42db05c1f9a182b506c2957271402992655591dd7c"
//   docker exec r swift build --swift-sdk swift-6.3.2-RELEASE_wasm-embedded
//
// Expected: signal 11 SIGSEGV during pass `MandatoryPerformanceOptimizations`
// while evaluating ExecuteSILPipelineRequest on the Consumer module's SIL.
//
// Package.swift:
//   // swift-tools-version: 6.3
//   import PackageDescription
//   let package = Package(
//       name: "repro",
//       targets: [
//           .target(name: "Consumer", dependencies: [
//               .product(name: "Index Primitives", package: "swift-index-primitives"),
//           ]),
//       ],
//       dependencies: [
//           .package(url: "https://github.com/swift-primitives/swift-index-primitives.git",
//                    branch: "main"),
//       ]
//   )
//
// Sources/Consumer/Consumer.swift (this file):

public import Index_Primitives

public let x: Index<Int> = .zero + .zero
