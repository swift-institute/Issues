//
//  IO.Event.Selector.Make.Error.swift
//  swift-io
//
//  Created by Coen ten Thije Boonkkamp on 28/12/2025.
//

extension IO.Event.Selector.Make {
    /// Errors that can occur during selector construction.
    ///
    /// This is a construction-specific error type, separate from runtime
    /// I/O errors (`IO.Event.Error`) and lifecycle errors (`Failure`).
    public enum Error: Swift.Error {
        /// Driver failed to create handle or wakeup channel.
        case driver(IO.Event.Error)
    }
}

extension IO.Event.Selector.Make.Error {
    @inline(always)
    static func source<T: ~Copyable>(
        _ body: () throws(Kernel.Event.Driver.Error) -> T
    ) throws(IO.Event.Selector.Make.Error) -> T {
        do { return try body() } catch {
            switch error {
            case .platform(let code): throw .driver(.platform(code))
            case .invalidDescriptor: throw .driver(.invalidDescriptor)
            case .notRegistered: throw .driver(.notRegistered)
            }
        }
    }
}
