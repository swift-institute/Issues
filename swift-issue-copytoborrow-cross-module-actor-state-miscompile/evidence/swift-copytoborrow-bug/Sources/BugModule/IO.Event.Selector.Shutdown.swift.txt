//
//  IO.Event.Selector.Shutdown.swift
//  swift-io
//

extension IO.Event.Selector {
    /// Namespace for selector shutdown types.
    ///
    /// Contains the `Token` type that enforces single-shutdown
    /// at compile time via `~Copyable`.
    public enum Shutdown {}
}
