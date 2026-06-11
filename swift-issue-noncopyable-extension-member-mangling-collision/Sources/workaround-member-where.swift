// WORKAROUND 1 (verified, incl. depth-2 nesting): home both twins in the primary
// body and put the Copyable requirement in a member-level where clause (SE-0267).
// The member-where twin mangles with the plain nominal context (no extension
// segment): '$s…TreeO9UnboundedVAEyx_GycfC' vs the body twin's
// '$s…TreeOAARi_zrlE9UnboundedVAEyx_GycfC' — distinct.
// Command: swiftc -emit-object workaround-member-where.swift -o /tmp/wa1.o  → builds clean

public enum Tree<Element: ~Copyable> {}

extension Tree where Element: ~Copyable {
    public struct Unbounded: ~Copyable {
        @usableFromInline var _x: Int

        public init() { self._x = 0 }                          // body twin (~Copyable context)

        public init() where Element: Copyable { self._x = 0 }  // member-level where twin
    }
}

extension Tree.Unbounded: Copyable where Element: Copyable {}
