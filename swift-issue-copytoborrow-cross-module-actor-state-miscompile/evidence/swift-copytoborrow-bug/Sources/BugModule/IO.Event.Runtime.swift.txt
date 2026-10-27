//
//  IO.Event.Runtime.swift
//  swift-io
//

public import Kernel
import Async
import Ownership_Primitives
internal import Synchronization

extension IO.Event {
    /// The coordination actor for the I/O event system.
    ///
    /// Pinned to the integrated event loop via `unownedExecutor` — all actor
    /// methods run on the executor thread, off the cooperative pool.
    ///
    /// ## Architecture (Phase 3 — Integrated Event Loop)
    ///
    /// ```
    /// [Selector]  --register/deregister--> [Runtime (actor)]
    /// [Channel]   --await arm------------> [Runtime (actor)]
    /// [Runtime]   --executor.withSource--> [Driver.register/arm/etc]
    /// [Loop]      --poll + dispatch------> [Channel senders]
    /// ```
    ///
    /// The Runtime calls the driver directly via `executor.withSource` — no
    /// request queue, no continuation bridge. Actor methods and the run loop
    /// both run on the same thread; the executor owns the driver in heap
    /// storage accessible to both.
    ///
    /// Owns lifecycle state (admission, shutdown). All I/O operations
    /// (register, deregister, arm, modify) are actor methods that serialize
    /// naturally via actor isolation.
    package actor Runtime {
        /// The integrated event loop executor.
        let executor: IO.Event.Loop

        /// Lifecycle state — actor-isolated, no atomics needed.
        private var state: State = .running

        nonisolated package var unownedExecutor: UnownedSerialExecutor {
            executor.asUnownedSerialExecutor()
        }

        package init(executor: IO.Event.Loop) {
            self.executor = executor
        }
    }
}

// MARK: - State

extension IO.Event.Runtime {
    enum State {
        case running
        case shuttingDown
    }
}

// MARK: - Registration

extension IO.Event.Runtime {
    package func register(
        descriptor: borrowing Kernel.Descriptor,
        interest: IO.Event.Interest
    ) throws(IO.Event.Failure) {
        guard state == .running else { throw .shutdownInProgress }
        do {
            _ = try Kernel.Descriptor.Duplicate.duplicate(descriptor)
        } catch {
            throw .failure(.invalidDescriptor)
        }
    }
}

// MARK: - Shutdown

extension IO.Event.Runtime {
    /// Shut down the event system.
    ///
    /// Two-phase shutdown:
    /// 1. **Reject**: set state to `.shuttingDown` — future `enter()` throws
    /// 2. **Halt**: close all senders, deregister all, signal loop to exit
    ///
    /// Runs as an actor method on the executor thread. After it returns, the
    /// `Scope.close()` method joins the executor thread via `executor.shutdown()`.
    @discardableResult
    package func shutdown() async -> Bool {
        guard state == .running else { return false }
        state = .shuttingDown
        executor.shouldHalt = true
        return true
    }
}
