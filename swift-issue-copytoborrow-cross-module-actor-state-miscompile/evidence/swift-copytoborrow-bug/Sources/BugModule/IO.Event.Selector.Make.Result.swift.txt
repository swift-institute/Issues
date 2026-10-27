//
//  IO.Event.Selector.Make.Result.swift
//  swift-io
//

extension IO.Event.Selector.Make {
    /// Bundle returned by `Selector.make()`.
    ///
    /// Contains the selector handle and its `~Copyable` shutdown token.
    ///
    /// ```swift
    /// var result = try await IO.Event.Selector.make()
    /// let selector = result.selector
    /// let token = result.token()
    /// ```
    public struct Result: ~Copyable, Sendable {
        /// The selector handle. Copyable — shared by channels.
        public let selector: IO.Event.Selector

        /// The shutdown token.
        private var _token: IO.Event.Selector.Shutdown.Token?

        package init(
            selector: IO.Event.Selector,
            token: consuming IO.Event.Selector.Shutdown.Token
        ) {
            self.selector = selector
            self._token = consume token
        }

        /// Take the shutdown token.
        ///
        /// Returns the token exactly once; subsequent calls return `nil`.
        public mutating func token() -> IO.Event.Selector.Shutdown.Token? {
            _token.take()
        }
    }
}
