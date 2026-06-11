// Control: the overload pair is semantically meaningful and Sema resolves it.
// `swiftc -typecheck overload-resolution-control.swift` PASSES — call sites
// statically bind the matching twin (more-constrained wins at Copyable sites).
// Only symbol emission fails (see reproducer.swift).

enum Tree<Element: ~Copyable> {}

extension Tree where Element: ~Copyable {
    enum Builder {
        static func build() -> Int { 0 }
    }
}

extension Tree.Builder where Element: Copyable {
    static func build() -> Int { 1 }
}

struct NC: ~Copyable {}

let a = Tree<Int>.Builder.build()   // resolves the Copyable twin
let b = Tree<NC>.Builder.build()    // resolves the body twin
print(a, b)
