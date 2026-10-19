// Index executable: prints where the authoritative reproducer lives.
// SwiftPM treats a file named main.swift as top-level code, so this is
// top-level rather than an @main type.

print("Dossier: swift-issue-noncanonical-existential-windows-debuginfo-ice")
print("Authoritative reproduction (Windows, Swift +Asserts, debug):")
print("  swift build -c debug --package-path evidence/source/cross-package/crash --target CrashModule")
print("Controls: --target RespellModule (canonical spelling) and")
print("  swiftc -Onone -g -c evidence/source/noncanonical-existential-debuginfo.swift (single module) stay clean.")
print("Run them against evidence/source; this index does not flatten the package boundary.")
