#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// A package with no dependencies. `swift package dump-package` runs three times against one
// fresh manifest cache: twice with X=A, then with X=B. The manifest never reads X.
// Exit 1 when the third run compiles the manifest again.
var template = Array("/tmp/repro-XXXXXX".utf8CString)
let base = String(cString: mkdtemp(&template)!)
mkdir("\(base)/p", 0o755)
let file = fopen("\(base)/p/Package.swift", "w")!
fputs("// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"p\")\n", file)
fclose(file)
chdir("\(base)/p")

/// Whether `dump-package`, run with X set to `value`, compiled the manifest (`-v` prints the compile command).
func compiles(_ value: String) -> Bool {
    let script = "X=\(value) swift package --cache-path ../cache -v dump-package 2>&1 | grep -q -- '-o [^ ]*p-manifest'"
    let arguments = ["/bin/sh", "-c", script].map { strdup($0) } + [nil]
    var pid: pid_t = 0
    var status: Int32 = 0
    posix_spawn(&pid, "/bin/sh", nil, nil, arguments, environ)
    waitpid(pid, &status, 0)
    return status == 0
}

guard compiles("A"), !compiles("A") else {
    print("no verdict: the first run must compile the manifest and the second must reuse it")
    exit(2)
}
if compiles("B") {
    print("the manifest was compiled again although only X changed")
    exit(1)
}
print("the manifest was reused")
