#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// root depends on b and on m. m asks for b's trait T but uses none of b's products.
// T guards b's dependency on c. Exit 1 (SwiftPM's status) when resolution fails.
let manifests = [
    "c": #"Package(name: "c", products: [.library(name: "C", targets: ["C"])], targets: [.target(name: "C")])"#,
    "b": #"Package(name: "b", products: [.library(name: "B", targets: ["B"])], traits: ["T"], dependencies: [.package(path: "../c")], targets: [.target(name: "B", dependencies: [.product(name: "C", package: "c", condition: .when(traits: ["T"]))])])"#,
    "m": #"Package(name: "m", dependencies: [.package(path: "../b", traits: ["T"])])"#,
    "root": #"Package(name: "root", dependencies: [.package(path: "../b"), .package(path: "../m")])"#,
]
var template = Array("/tmp/repro-XXXXXX".utf8CString)
let base = String(cString: mkdtemp(&template)!)
for (name, manifest) in manifests {
    mkdir("\(base)/\(name)", 0o755)
    let file = fopen("\(base)/\(name)/Package.swift", "w")!
    fputs("// swift-tools-version: 6.1\nimport PackageDescription\nlet package = \(manifest)\n", file)
    fclose(file)
}
chdir("\(base)/root")
let command: [String] = ["swift", "package", "resolve"]
execvp("swift", command.map { strdup($0) } + [nil])
