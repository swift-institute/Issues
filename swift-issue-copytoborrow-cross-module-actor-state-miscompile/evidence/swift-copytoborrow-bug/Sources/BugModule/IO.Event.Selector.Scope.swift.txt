//
//  IO.Event.Selector.Scope.swift
//  swift-io
//

internal import Synchronization

extension IO.Event.Selector {
    /// Scope-bound selector.
    ///
    /// `~Copyable`: single owner, consuming `close()` can be called at most once.
    /// `~Escapable`: cannot be stored in properties, returned, or captured
    ///   in escaping closures — confined to its lexical scope.
    /// Not `Sendable`: cannot be sent to a Task.
    ///
    /// ## Shutdown Token
    ///
    /// The scope holds a `~Copyable` shutdown token in a `Mutex<Token?>`.
    /// `close()` takes the token and executes it. If `close()` is never
    /// called, `deinit` takes the token and performs emergency sync cleanup.
    ///
    /// Double-shutdown is a compile-time error — the token can only be
    /// consumed once, and `close()` is consuming on the `~Copyable` scope.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let scope = try await IO.Event.Selector.Scope()
    /// let selector = scope.selector
    /// // ... use selector ...
    /// await scope.close()
    /// ```
    public struct Scope: ~Copyable, ~Escapable {
        /// The selector handle. Copyable — shared by channels within the scope.
        public let selector: IO.Event.Selector

        /// Token wrapped in Mutex — workaround for `~Copyable`
        /// partial-consume-with-deinit limitation (V4 pattern).
        private let _token: Mutex<Shutdown.Token?>

        /// Create a scope-bound selector.
        ///
        /// Creates an integrated event loop executor with a single OS thread.
        /// The `IO.Event.Runtime` actor is pinned to this executor.
        ///
        /// - Throws: `Make.Error` if selector construction fails.
        @_lifetime(immortal)
        public init() async throws(Make.Error) {
            var result = try await IO.Event.Selector.make()
            self.selector = result.selector
            self._token = Mutex(result.token())
        }

        /// Shut down the selector.
        ///
        /// Consuming — after this call, the scope is dead. Takes the
        /// token from the mutex and executes the shutdown sequence, then
        /// joins the executor thread.
        public consuming func close() async {
            if let token = _token.withLock({ $0.take() }) {
                await token.execute()
                // Join the executor thread. Safe: close() runs after all structured
                // tasks have completed. The calling thread is NOT the executor thread.
                selector.executor.shutdown()
            }
        }

        deinit {
            if let _ = _token.withLock({ $0.take() }) {
                // Emergency fallback: token was never consumed via close().
                // Cannot run async shutdown in deinit — spawn an unstructured Task
                // to run the actor shutdown method. Thread is NOT joined; the
                // emergency cleanup runs best-effort.
                let capturedRuntime = selector.runtime
                Task {
                    await capturedRuntime.shutdown()
                }
            }
        }
    }
}
