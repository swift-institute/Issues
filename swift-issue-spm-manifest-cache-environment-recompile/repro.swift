#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// A package with no dependencies, whose manifest never reads X. `dump-package` runs three times
// against one fresh manifest cache: twice with X=A, then with X=B. Exit 1 when the third run
// compiles the manifest again (`-v` prints the command that links it).
var template = Array("/tmp/repro-XXXXXX".utf8CString)
chdir(mkdtemp(&template)!)
let file = fopen("Package.swift", "w")!
fputs("// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"p\")\n", file)
fclose(file)

func compiles(_ value: String) -> Bool {
    let script = "X=\(value) swift package --cache-path cache -v dump-package 2>&1 | grep -q -- -manifest"
    var pid: pid_t = 0
    var status: Int32 = 0
    posix_spawn(&pid, "/bin/sh", nil, nil, ["/bin/sh", "-c", script].map { strdup($0) } + [nil], environ)
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
