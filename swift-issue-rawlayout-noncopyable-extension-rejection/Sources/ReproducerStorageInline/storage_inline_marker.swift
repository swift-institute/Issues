// ===----------------------------------------------------------------------===//
//
// swift-issue-rawlayout-noncopyable-extension-rejection
//
// THE TRIGGER FILE.
//
// The unconditional protocol conformance below — `extension Storage.Inline: Marker`
// without `where Element: ~Copyable` — introduces an implicit `Element: Copyable`
// requirement on the extension (per SE-0427 Noncopyable Generics: "An extension
// of a concrete type must introduce a default `T: Copyable` requirement on
// every generic parameter of the extended type"). The bug is that this
// implicit constraint leaks back to the PRIMARY declaration in
// `storage_inline.swift`, breaking the body's reference to `Element` even
// though the primary declaration is correctly scoped under
// `extension Storage where Element: ~Copyable`.
//
// THE WORKAROUND (Workaround D in INVESTIGATION-ARC.md):
//
//   extension Storage.Inline: Marker where Element: ~Copyable {
//       public typealias Element = Element
//   }
//
// Adding `where Element: ~Copyable` to the conformance extension suppresses
// the default `Element: Copyable` constraint, eliminating the leak.
//
// ===----------------------------------------------------------------------===//

public import StorageNamespaceLib

// The bug-triggering line — unconditional conformance without
// `where Element: ~Copyable`. Replace with:
//   extension Storage.Inline: Marker where Element: ~Copyable {
// to apply Workaround D and observe a clean build.
extension Storage.Inline: Marker {
    public typealias Element = Element
}
