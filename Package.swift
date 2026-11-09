// swift-tools-version: 6.4

import Foundation
import PackageDescription

// Every swift-issue-<topic>/ folder listed below becomes a test target, <topic>-Tests, built
// from its Tests/ folder, and, when Sources/Reproducer/ holds Swift sources, an
// executable target, <topic>-Repro. Files other than .swift files in those two folders are
// inputs the harness compiles out of process, so they're excluded from the
// build. A folder that doesn't have the layout fails here or in `issue-check
// --layout`; its record is the issue named in its ISSUE file.

let root = URL(fileURLWithPath: Context.packageDirectory)
let files = FileManager.default

@MainActor
func excluded(_ path: String) -> [String] {
    let entries = (try? files.contentsOfDirectory(atPath: root.appendingPathComponent(path).path)) ?? []
    return entries.filter { !$0.hasSuffix(".swift") }.sorted()
}

// The folders, listed so the manifest text changes when one is added or removed:
// SwiftPM caches a manifest by its text, so a listing from the file system would
// go stale. `issue-check --layout` fails when this list and the folders differ.
let folders = [
    "swift-issue-ast-verifier-member-attribute-macro-enum-case",
    "swift-issue-astscope-member-attribute-macro-overlapping-scopes",
    "swift-issue-async-uint128-argument-aarch64-linux",
    "swift-issue-borrowing-class-to-anyobject-conversion",
    "swift-issue-conditional-extension-typealias-name-capture",
    "swift-issue-copypropagation-noncopyable-observer-leak",
    "swift-issue-copytoborrow-cross-module-actor-state-miscompile",
    "swift-issue-debuginfo-integer-generic-above-uint32",
    "swift-issue-extension-table-uint16-datalength-overflow",
    "swift-issue-irgen-apply-argument-thin-function-large-struct",
    "swift-issue-irgen-null-type-nested-typed-throws",
    "swift-issue-irgen-typed-throws-closure-untyped-parameter",
    "swift-issue-isolated-parameter-guard-let-capture-executor",
    "swift-issue-keypath-dynamic-member-chain-root-assertion",
    "swift-issue-loadable-by-address-thin-function-large-struct",
    "swift-issue-macro-conformance-public-import-accounting",
    "swift-issue-macro-extension-conformance-inherited-secondary-file",
    "swift-issue-memory-lifetime-consuming-get-protocol-extension",
    "swift-issue-move-checker-let-field-consuming-self-copy",
    "swift-issue-nested-ambiguity-failed-to-produce-diagnostic",
    "swift-issue-noncopyable-assoctype-never-bodyless-witness",
    "swift-issue-noncopyable-assoctype-second-protocol-bodyless-witness",
    "swift-issue-noncopyable-extension-member-mangling-collision",
    "swift-issue-noncopyable-get-requirement-borrow",
    "swift-issue-noncopyable-rawlayout-trailing-field-miscompile",
    "swift-issue-noncopyable-sametype-conditional-conformance",
    "swift-issue-noncopyable-sequence-conformance",
    "swift-issue-pointer-arithmetic-linux-miscompile",
    "swift-issue-protocol-typealias-parent-noncanonical",
    "swift-issue-rawlayout-noncopyable-extension-rejection",
    "swift-issue-runtime-generic-sending-closure-task-dealloc",
    "swift-issue-runtime-value-generic-nested-generic-metadata",
    "swift-issue-sendnonsendable-iife-borrowing-init-crash",
    "swift-issue-sil-verifier-error-debug-value-async-typed-throws-call",
    "swift-issue-silgen-borrowed-base-modify-through-read",
    "swift-issue-silgen-pack-expansion-tuple-argument",
    "swift-issue-silgen-property-wrapper-noncopyable-member",
    "swift-issue-silgen-sendable-typed-throws-closure-cast",
    "swift-issue-silgen-term-verification-primary-associated-type-noncopyable",
    "swift-issue-silgencleanup-nested-closure-borrowing-noncopyable",
    "swift-issue-sillinker-borrowed-protocol-default-shared-coroutine-abort",
    "swift-issue-span-of-throwing-temporary-cleanup-dominance",
    "swift-issue-spm-diamond-trait-conditional-dependency",
    "swift-issue-spm-dotted-test-target-runner-linux",
    "swift-issue-spm-implied-trait-conditional-dependency",
    "swift-issue-spm-unused-dependency-trait-request",
    "swift-issue-static-exclusivity-library-evolution-noncopyable-span",
    "swift-issue-swift-format-shorthand-drops-module-selector",
    "swift-issue-swiftlint-redundant-nil-coalescing-double-optional",
    "swift-issue-swiftlint-synthesized-initializer-fix-beyond-lint",
    "swift-issue-testing-foundation-overlay-package-system-module",
    "swift-issue-typed-throws-autoclosure-never-inference",
    "swift-issue-typed-throws-catch-clause-error-conversion",
    "swift-issue-typeresolution-unbound-outer-generic-alias-crash",
    "swift-issue-unbound-generic-typealias-member-lookup",
    "swift-issue-windows-isexecutablefile-missing-file",
    "swift-issue-windows-string-init-regexparser-ambiguity",
]

let targets: [Target] = folders.flatMap { folder -> [Target] in
    var result: [Target] = [
        .testTarget(
            name: "\(folder)-Tests",
            path: "\(folder)/Tests",
            exclude: excluded("\(folder)/Tests")
        )
    ]
    let reproducer = "\(folder)/Sources/Reproducer"
    let sources = (try? files.contentsOfDirectory(atPath: root.appendingPathComponent(reproducer).path)) ?? []
    if sources.contains(where: { $0.hasSuffix(".swift") }) {
        result.append(
            .executableTarget(
                name: "\(folder)-Repro",
                path: reproducer,
                exclude: excluded(reproducer)
            )
        )
    }
    return result
}

let package = Package(
    name: "Issues",
    platforms: [.macOS(.v27), .iOS(.v27), .tvOS(.v27), .watchOS(.v27), .visionOS(.v27)],
    targets: targets,
    swiftLanguageModes: [.v6]
)

for target in package.targets {
    target.swiftSettings = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableExperimentalFeature("Lifetimes"),
        .treatAllWarnings(as: .error),
    ]
}
