//
//  IO.Event.Selector.swift
//  swift-io
//

public import Kernel
import Async
import Ownership_Primitives
internal import Synchronization

extension IO.Event {
    public struct Selector: Sendable {
        package let executor: IO.Event.Loop
        package let runtime: IO.Event.Runtime

        private init(executor: IO.Event.Loop, runtime: IO.Event.Runtime) {
            self.executor = executor
            self.runtime = runtime
        }
    }
}

// MARK: - Factory

extension IO.Event.Selector {
    package static func make() async throws(Make.Error) -> Make.Result {
        let source = try Make.Error.source {
            () throws(Kernel.Event.Driver.Error) -> Kernel.Event.Source in
            try Kernel.Event.Source.platform()
        }
        return try await make(source)
    }

    package static func make(
        _ source: consuming Kernel.Event.Source
    ) async throws(Make.Error) -> Make.Result {
        let (executor, runtime) = _makeCore(source)
        return Make.Result(
            selector: IO.Event.Selector(executor: executor, runtime: runtime),
            token: Shutdown.Token(runtime: runtime)
        )
    }

    private static func _makeCore(
        _ source: consuming Kernel.Event.Source
    ) -> (IO.Event.Loop, IO.Event.Runtime) {
        let executor = IO.Event.Loop(source: source)
        let runtime = IO.Event.Runtime(executor: executor)
        return (executor, runtime)
    }
}

// MARK: - Registration

extension IO.Event.Selector {
    /// Register — the public API that triggers the actor hop.
    package func register(
        _ descriptor: borrowing Kernel.Descriptor,
        interest: IO.Event.Interest
    ) async throws(IO.Event.Failure) {
        try await _register(descriptor, interest: interest, on: runtime)
    }

    /// Runs on the runtime's executor via `isolated Runtime` parameter.
    private func _register(
        _ descriptor: borrowing Kernel.Descriptor,
        interest: IO.Event.Interest,
        on runtime: isolated IO.Event.Runtime
    ) throws(IO.Event.Failure) {
        try runtime.register(
            descriptor: descriptor,
            interest: interest
        )
    }
}
