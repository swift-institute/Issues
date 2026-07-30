// Index executable: prints where the authoritative reproducer lives.
// SwiftPM treats a file named main.swift as top-level code, so this is
// top-level rather than an @main type.

print("Canonical issue: https://github.com/swift-institute/Issues/issues/14")
print("Dossier: swift-issue-rawlayout-deinit-cross-package")
print("Authoritative reproduction command: swift test")
print("Run the command against evidence/source-package; this index does not flatten the source boundary.")
