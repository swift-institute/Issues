//
//  IO.Event.Selector.Shutdown.Token.swift
//  swift-io
//

extension IO.Event.Selector.Shutdown {
    /// A `~Copyable` token that must be consumed to trigger shutdown.
    ///
    /// Makes double-shutdown a compile-time error. Produced by
    /// `Selector.make()`, consumed by `Scope.close()` or directly
    /// via `execute()`.
    ///
    /// ## Design
    ///
    /// - `~Copyable`: consuming `execute()` can be called exactly once
    /// - `Sendable`: can cross isolation boundaries
    /// - No `deinit`: pure capability — emergency cleanup is Scope's responsibility
    ///
    /// ## Usage
    ///
    /// ```swift
    /// var result = try await IO.Event.Selector.make()
    /// let selector = result.selector
    /// let token = result.token()!
    /// // ... use selector ...
    /// await token.execute()
    /// ```
    public struct Token: ~Copyable, Sendable {
        /// The runtime actor for multi-phase shutdown coordination.
        private let runtime: IO.Event.Runtime

        package init(runtime: IO.Event.Runtime) {
            self.runtime = runtime
        }

        /// Execute the four-phase shutdown sequence.
        ///
        /// Consuming — the compiler rejects any second call.
        @discardableResult
        public consuming func execute() async -> Bool {
            await runtime.shutdown()
        }
    }
}
