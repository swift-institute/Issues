// ===----------------------------------------------------------------------===//
//
// swift-issue-rawlayout-noncopyable-extension-rejection
//
// Module B — declares `Storage<Element>.Inline` and conforms it to `Marker`.
//
// The error fires at `_ = Element.self` INSIDE the primary type body
// (Storage.Inline.foo), not in the conformance extension. The implicit
// `Element: Copyable` constraint introduced by the unconditional conformance
// `extension Storage.Inline: Marker { … }` leaks back to the primary
// declaration, contradicting the outer `extension Storage where Element: ~Copyable`.
//
// To make the reproducer fire, build this module with:
//
//   swiftc -module-name StorageInlineLib -I . -L . -lStorageNamespaceLib \
//          -emit-module -emit-library -enable-library-evolution \
//          -enable-upcoming-feature InternalImportsByDefault \
//          -enable-upcoming-feature MemberImportVisibility \
//          -enable-experimental-feature LifetimeDependence \
//          -enable-experimental-feature SuppressedAssociatedTypes \
//          -enable-experimental-feature RawLayout \
//          storage_inline.swift storage_inline_marker.swift
//
// Expected error (Swift 6.3.2 default + 6.4-dev nightly):
//
//   storage_inline.swift:N:K: error: type 'Element' does not conform to protocol 'Copyable'
//
// ===----------------------------------------------------------------------===//

public import StorageNamespaceLib

extension Storage where Element: ~Copyable {
    public struct Inline<let capacity: Int>: ~Copyable {
        // `@_rawLayout` references `Element` — mirrors the production trigger
        // site at Storage.Inline.swift line 97 in swift-storage-primitives.
        // Per V13 (no deinit, only @_rawLayout) the @_rawLayout reference alone
        // is enough to trigger the error when the unconditional conformance is
        // present. The @_rawLayout itself is NOT required for the trigger —
        // any reference to `Element` in the primary type's body suffices.
        @_rawLayout(likeArrayOf: Element, count: capacity)
        public struct _Raw: ~Copyable { public init() {} }

        public var _storage: _Raw
        public init() { _storage = _Raw() }

        // The deinit body's `Element.self` reference reproduces the production
        // trigger at Storage.Inline.swift lines 139/142/143. Per V12 / V15 /
        // V17, ANY reference to `Element` inside the inner type's body
        // (deinit OR regular method OR @_rawLayout) is sufficient. The
        // production code happens to reference Element in all three sites.
        deinit {
            _ = Element.self
        }
    }
}
