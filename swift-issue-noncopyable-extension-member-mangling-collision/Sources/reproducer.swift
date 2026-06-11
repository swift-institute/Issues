// Minimal reproducer — body member vs redundant-with-default `where Element: Copyable`
// extension member of an extension-nested type mangle to the same symbol.
// Command: swiftc -emit-object reproducer.swift -o /tmp/repro.o
// Observed: error: multiple definitions of symbol '$s…TreeOAARi_zrlE7BuilderO5buildyyFZ'
// `swiftc -typecheck reproducer.swift` PASSES — Sema accepts the pair as distinct overloads.

enum Tree<Element: ~Copyable> {}

extension Tree where Element: ~Copyable {
    enum Builder {
        static func build() {}
    }
}

extension Tree.Builder where Element: Copyable {
    static func build() {}
}
