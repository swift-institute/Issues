//
//  IO.Event.Loop.swift
//  swift-io
//

public import Kernel
import Async
import Ownership_Primitives
import Buffer_Primitives

extension IO.Event {
    /// An integrated I/O event loop: `SerialExecutor + TaskExecutor + poll`.
    ///
    /// Merges the executor thread and the poll thread into a single OS thread.
    /// The run loop interleaves actor job dispatch with kernel event polling:
    ///
    /// ```
    /// drain jobs → poll(deadline) → dispatch events → repeat
    /// ```
    ///
    /// ## Source Ownership
    ///
    /// The `~Copyable` event source is stored directly on this class.
    /// Both the run loop (sync `poll()` call) and the `IO.Event.Runtime`
    /// actor (via `withSource { ... }`) access it on the executor thread
    /// — single-threaded, race-free.
    ///
    /// ## Architecture
    ///
    /// - One OS thread per event loop
    /// - Actor pinned via `unownedExecutor` — compiler-verified isolation
    /// - All I/O state is thread-confined — no locks on the hot path
    /// - Cross-thread entry is limited to `enqueue()` (job dispatch)
    ///
    /// ## Thread Safety
    ///
    /// `@unchecked Sendable` because it provides internal synchronization.
    /// The job queue is lock-protected for cross-thread `enqueue()`.
    /// All other state is thread-confined to the executor's OS thread.
    public final class Loop: SerialExecutor, TaskExecutor, @unchecked Sendable {

        // MARK: - Thread-safe state (cross-thread access via enqueue)

        /// Mutex for the job queue and isRunning flag.
        private let sync: Kernel.Thread.Synchronization<1>

        /// Pending actor jobs. Protected by `sync`.
        private var jobs: ContiguousArray<UnownedJob> = []

        /// Buffer for batch-draining jobs. Only accessed on the executor thread.
        private var drainBuffer: ContiguousArray<UnownedJob> = []

        /// Run loop alive flag. Set to `false` just before the run loop exits.
        /// Checked by `enqueue()` under `sync` lock to decide inline execution.
        private var isRunning: Bool = true

        /// OS thread handle. Taken by `shutdown()` for join, or by `deinit` for detach.
        private var threadHandle: Kernel.Thread.Handle?

        // MARK: - Wakeup (private — interrupts blocking poll)

        /// Wakeup channel — interrupts `poll()` when jobs arrive via `enqueue()`.
        /// Extracted from the driver before the driver is placed in heap storage.
        private let wakeup: IO.Event.Wakeup.Channel

        // MARK: - Source storage (stored directly; Loop is already a class)

        /// The `~Copyable` event source (Kernel.Event.Source).
        ///
        /// Optional wrapper lets `deinit` `take()` and consume the source
        /// to call its consuming `close()`. Thread-confined to the executor
        /// thread; the class's `@unchecked Sendable` conformance covers it.
        ///
        /// Accessed by:
        /// - `runLoop()` for `poll()` (sync, executor thread)
        /// - `withSource()` called from actor methods (executor thread)
        private var source: Kernel.Event.Source?

        /// Maximum events per poll cycle.
        private static let maxEventsPerPoll = 256

        // MARK: - Halt flag (set by Runtime.shutdown() to exit the run loop)

        /// Set to `true` when shutdown is requested. Checked by the run loop
        /// after draining jobs. Accessed only on the executor thread.
        var shouldHalt: Bool = false

        // MARK: - Registration table (stubbed for elimination experiment)
        // Removed: registrations dictionary (Registration type removed)

        // MARK: - Init

        /// Creates an integrated event loop executor.
        ///
        /// Extracts the wakeup channel from the source, stores the source,
        /// and spawns the OS thread that runs the event loop.
        ///
        /// - Parameter source: The platform event source. Consumed — ownership
        ///   transfers to the Loop's source slot.
        init(source: consuming Kernel.Event.Source) {
            self.wakeup = IO.Event.Wakeup.Channel(source.wakeup)
            self.sync = Kernel.Thread.Synchronization()
            self.source = consume source

            // Transfer a retained self reference to the new OS thread.
            self.threadHandle = unsafe Kernel.Thread.trap(Ownership.Transfer.Retained(self)) { retained in
                let executor = retained.take()
                executor.runLoop()
            }
        }

        deinit {
            if let handle = threadHandle.take() {
                // Emergency: shutdown was never called. Halt and detach.
                shouldHalt = true
                wakeup.wake()
                handle.detach()
            }

            // Consume and close the source. This is the SINGLE close point —
            // keeping the source alive until deinit ensures that actor methods
            // running as inline jobs after shutdown see a valid source (though
            // their operations may be no-ops if resources are already drained).
            if let taken = source.take() {
                taken.close()
            }
        }
    }
}

// MARK: - SerialExecutor

extension IO.Event.Loop {
    /// Enqueue a job for execution on the event loop thread.
    ///
    /// Thread-safe. If the run loop has exited, the job runs inline on the
    /// calling thread (honors the SerialExecutor contract).
    ///
    /// When the run loop is alive, the job is added to the queue and the
    /// wakeup channel interrupts any blocking `poll()` call.
    public func enqueue(_ job: UnownedJob) {
        let runInline: Bool = sync.withLock {
            guard isRunning else { return true }
            jobs.append(job)
            return false
        }
        if runInline {
            unsafe job.runSynchronously(on: asUnownedSerialExecutor())
        } else {
            wakeup.wake()
        }
    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        unsafe UnownedSerialExecutor(ordinary: self)
    }
}

// MARK: - TaskExecutor

extension IO.Event.Loop {
    public func enqueue(_ job: consuming ExecutorJob) {
        enqueue(UnownedJob(job))
    }
}

// withSource removed — Runtime no longer calls it in reduced module

// MARK: - Run Loop

extension IO.Event.Loop {
    /// The integrated event loop.
    ///
    /// Three phases per iteration:
    /// 1. **Drain jobs**: execute all pending actor jobs
    /// 2. **Poll**: block in `kevent`/`epoll_wait` until events or wakeup
    /// 3. **Dispatch**: send events to channel senders
    ///
    /// The loop exits when `shouldHalt` is set (by `Runtime.shutdown()`).
    private func runLoop() {
        var eventBuffer = Array<Kernel.Event>(
            repeating: .empty,
            count: Self.maxEventsPerPoll
        )

        while true {
            drainJobs()
            if shouldHalt { break }

            // Poll — blocks until events or wakeup.
            let count = (try? self.source!.poll(deadline: nil, into: &eventBuffer)) ?? 0
            if count > 0 { dispatchEvents(buffer: &eventBuffer, count: count) }
        }

        shutdownCleanup()
    }

    /// Drain all pending actor jobs.
    ///
    /// Swaps the job queue to a drain buffer under lock (O(1)), then
    /// executes all jobs. Jobs enqueued during execution accumulate in
    /// the (now empty) queue and are picked up on the next drain call.
    private func drainJobs() {
        while true {
            sync.withLock {
                swap(&self.jobs, &self.drainBuffer)
            }
            guard !self.drainBuffer.isEmpty else { return }
            for job in self.drainBuffer {
                unsafe job.runSynchronously(on: self.asUnownedSerialExecutor())
            }
            self.drainBuffer.removeAll(keepingCapacity: true)
        }
    }

    /// Stubbed for elimination experiment.
    private func dispatchEvents(buffer: inout [Kernel.Event], count: Int) {}

    // MARK: - Shutdown

    /// Normal shutdown: finalize job drain and mark the executor stopped.
    ///
    /// The source stays valid until `deinit` — this lets inline jobs
    /// (e.g., lingering `selector.rearm()` calls after the run loop exits)
    /// still call `withSource` without crashing on a nil slot.
    private func shutdownCleanup() {
        drainJobs()
        sync.withLock {
            isRunning = false
        }
    }

    /// Stubbed for elimination experiment.
    private func fatalCleanup(error: IO.Event.Error) {
        drainJobs()
        sync.withLock { isRunning = false }
    }
}

// MARK: - Shutdown (public)

extension IO.Event.Loop {
    /// Shut down the executor by joining its OS thread.
    ///
    /// The run loop must have already been halted (via `Runtime.shutdown()`
    /// setting `shouldHalt = true`). This method blocks until the thread exits.
    ///
    /// - Precondition: Must NOT be called from the executor's own thread.
    /// - Precondition: Must be called at most once.
    func shutdown() {
        guard let handle = threadHandle.take() else {
            preconditionFailure(
                "IO.Event.Loop.shutdown() called on already-shutdown executor"
            )
        }

        precondition(
            !handle.isCurrent,
            "Cannot shutdown executor from its own thread — would deadlock on join"
        )

        handle.join()
    }
}
