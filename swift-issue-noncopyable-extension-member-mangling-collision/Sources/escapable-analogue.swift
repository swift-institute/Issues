// The defect generalizes to the other invertible protocol: an ~Escapable-suppressed
// parameter with a redundant-with-default `Escapable` extension requirement collides
// identically (inverse index 1: `Ri0_zrl`).
// Command: swiftc -emit-object escapable-analogue.swift -o /tmp/esc.o
// Observed: error: multiple definitions of symbol '$s…TreeOAARi0_zrlE9UnboundedVAEyx_GycfC'

public enum Tree<Element: ~Escapable> {}

extension Tree where Element: ~Escapable {
    public struct Unbounded {
        @usableFromInline var _x: Int
        public init() { self._x = 0 }
    }
}

extension Tree.Unbounded where Element: Escapable {
    public init() { self._x = 0 }
}
