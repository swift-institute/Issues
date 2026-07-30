// Index executable: prints where the authoritative reproducer lives.
// SwiftPM treats a file named main.swift as top-level code, so this is
// top-level rather than an @main type.

print("Canonical issue: https://github.com/swift-institute/Issues/issues/15")
print("Dossier: swift-issue-sil-verifier-read-escapable-lifetime")
print("Authoritative reproduction command: swift build")
print("Run the command against evidence/source-package; this index does not flatten the source boundary.")
