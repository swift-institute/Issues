// The production shape (constructing-twin inits, [MEM-COPY-017]) — the form in which
// swift-stack-primitives 7e4200a and the tree packages 7137543/d116555/c6f9888 hit this.
// Command: swiftc -emit-object production-shape-init.swift -o /tmp/prod.o
// Observed: error: multiple definitions of symbol
//   '$s…StackVAARi_zrlE7BoundedV8capacityAEyx_GSi_tcfC'

public struct Stack<Element: ~Copyable>: ~Copyable {}

extension Stack where Element: ~Copyable {
    public struct Bounded: ~Copyable {
        @usableFromInline var _x: Int

        public init(capacity: Int) { self._x = capacity }   // body twin (~Copyable context)
    }
}

extension Stack.Bounded where Element: Copyable {
    public init(capacity: Int) { self._x = capacity }       // extension twin
}

extension Stack.Bounded: Copyable where Element: Copyable {}
