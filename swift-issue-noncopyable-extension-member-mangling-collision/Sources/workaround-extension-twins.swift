// WORKAROUND 2 (verified, incl. depth-2 nesting): home BOTH twins in constrained
// extensions. The ~Copyable extension's inverse requirement IS mangled (second
// 'AARi_zrlE' segment): '$s…TreeOAARi_zrlE9UnboundedVAARi_zrlEAEyx_GycfC' vs the
// Copyable extension's dropped-requirement form '$s…TreeOAARi_zrlE9UnboundedVAEyx_GycfC'
// — distinct. (The Copyable extension member still occupies the body-member symbol,
// so this spelling requires the primary body to declare NO same-signature member.)
// Command: swiftc -emit-object workaround-extension-twins.swift -o /tmp/wa2.o  → builds clean

public enum Tree<Element: ~Copyable> {}

extension Tree where Element: ~Copyable {
    public struct Unbounded: ~Copyable {
        @usableFromInline var _x: Int
    }
}

extension Tree.Unbounded where Element: ~Copyable {
    public init() { self._x = 0 }                           // ~Copyable extension twin
}

extension Tree.Unbounded where Element: Copyable {
    public init() { self._x = 0 }                           // Copyable extension twin
}

extension Tree.Unbounded: Copyable where Element: Copyable {}
