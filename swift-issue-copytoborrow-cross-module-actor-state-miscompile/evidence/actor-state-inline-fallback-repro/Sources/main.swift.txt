// MARK: - Repro: actor state visibility via inline-fallback custom executor
//
// Hypothesis: when actor.shutdown() runs on the executor thread, then the
// caller's continuation resumes on a DIFFERENT cooperative-pool thread, then
// pthread_join is called on that cooperative thread, then runtime.register()
// is called and runs INLINE via Loop.enqueue's fallback on yet ANOTHER
// cooperative thread that did not participate in the join — the actor's
// state field can be read as the OLD value because no acquire-release chain
// connects the executor thread's writes to the inline-execution thread.
//
// Toolchain: Swift 6.3 (Xcode 26)
// Revalidated: Swift 6.3.1 (2026-04-17) — PASSES (0 stale reads across 1000 iters per scenario; the inline-fallback / cross-thread theories were ruled out as red herrings — see memory `copytoborrow-actor-state-barrier.md`)
// Platform: macOS 26 (arm64)
// Result: NOT REPRODUCED — actor state always observed as `.shuttingDown` after the writer thread completes; the real miscompile lives elsewhere (CopyToBorrowOptimization on Mutex<Token?> field — see `copytoborrow-actor-state-mutex-miscompile/`).

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Synchronization

// ==========================================================================
// MARK: - The Executor
// ==========================================================================

final class Loop: SerialExecutor, @unchecked Sendable {
    private let lock = Mutex<State>(State())

    private struct State: ~Copyable {
        var jobs: [UnownedJob] = []
        var isRunning: Bool = true
    }

    private var thread: pthread_t? = nil
    private var wakefd: (read: Int32, write: Int32) = (-1, -1)
    var shouldHalt: Bool = false

    init() {
        var fds: (Int32, Int32) = (-1, -1)
        let r = unsafe withUnsafeMutablePointer(to: &fds) { p in
            unsafe p.withMemoryRebound(to: Int32.self, capacity: 2) { unsafe pipe($0) }
        }
        precondition(r == 0, "pipe failed")
        self.wakefd = fds
    }

    func start() {
        let cself = unsafe Unmanaged.passRetained(self).toOpaque()
        var t: pthread_t? = nil
        let rc = unsafe pthread_create(&t, nil, { ptr in
            let s = unsafe Unmanaged<Loop>.fromOpaque(ptr).takeRetainedValue()
            s.run()
            return nil
        }, cself)
        precondition(rc == 0, "pthread_create failed")
        self.thread = t
    }

    deinit {
        unsafe close(wakefd.0)
        unsafe close(wakefd.1)
    }

    private func wake() {
        var b: UInt8 = 1
        _ = unsafe write(wakefd.write, &b, 1)
    }

    private func waitForWake() {
        var b: UInt8 = 0
        _ = unsafe read(wakefd.read, &b, 1)
    }

    func enqueue(_ job: UnownedJob) {
        let runInline: Bool = lock.withLock { state in
            guard state.isRunning else { return true }
            state.jobs.append(job)
            return false
        }
        if runInline {
            // Inline fallback — the SUSPECT pattern
            unsafe job.runSynchronously(on: asUnownedSerialExecutor())
        } else {
            wake()
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        unsafe UnownedSerialExecutor(ordinary: self)
    }

    private func run() {
        mainLoop: while true {
            while true {
                var batch: [UnownedJob] = []
                let hasMore = lock.withLock { state -> Bool in
                    if state.jobs.isEmpty { return false }
                    swap(&batch, &state.jobs)
                    return true
                }
                if !hasMore { break }
                for j in batch {
                    unsafe j.runSynchronously(on: asUnownedSerialExecutor())
                }
            }

            if shouldHalt { break mainLoop }
            waitForWake()
        }
        let _ = lock.withLock { state in
            state.isRunning = false
        }
    }

    func requestHalt() {
        shouldHalt = true
        wake()
    }

    func join() {
        if let t = thread {
            pthread_join(t, nil)
            thread = nil
        }
    }
}

// ==========================================================================
// MARK: - The Actor (mimics IO.Event.Runtime)
// ==========================================================================

actor Runtime {
    enum State {
        case running
        case shuttingDown
    }

    let loop: Loop
    private var state: State = .running

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        loop.asUnownedSerialExecutor()
    }

    init(loop: Loop) {
        self.loop = loop
    }

    struct ShutdownInProgress: Error {}
    struct InvalidDescriptor: Error {}

    func enter() throws {
        guard state == .running else { throw ShutdownInProgress() }
    }

    func register(id: Int) throws -> Int {
        // This mimics swift-io's Runtime.register: admission check + dup
        guard state == .running else { throw ShutdownInProgress() }
        // The "dup" is just a side-effect we want to fail later if state is wrong
        if id < 0 { throw InvalidDescriptor() }
        return id * 2
    }

    func shutdown() async {
        state = .shuttingDown
        loop.requestHalt()
    }
}

// ==========================================================================
// MARK: - Scenarios
// ==========================================================================

// Scenario A: shut down + join from the SAME thread that calls register
// (matches my first repro attempt)
@inline(never)
func scenarioA(loop: Loop, runtime: Runtime, id: Int) async -> Bool {
    await runtime.shutdown()
    loop.join()
    do {
        _ = try await runtime.register(id: id)
        return true // STALE
    } catch {
        return false // expected
    }
}

// Scenario B: spawn a child Task that performs shutdown+join
// then back on the parent we call register. The parent's resumption may
// happen on a different cooperative thread.
@inline(never)
func scenarioB(loop: Loop, runtime: Runtime, id: Int) async -> Bool {
    await Task { @Sendable in
        await runtime.shutdown()
        loop.join()
    }.value

    do {
        _ = try await runtime.register(id: id)
        return true // STALE
    } catch {
        return false // expected
    }
}

// Scenario C: many tasks racing register against a single shutdown,
// with the shutdown task explicitly hopping to a foreign queue before joining.
@inline(never)
func scenarioC(loop: Loop, runtime: Runtime, id: Int) async -> Bool {
    let shutdownDone = Task<Void, Never>.detached { @Sendable in
        await runtime.shutdown()
        loop.join()
    }
    await shutdownDone.value

    do {
        _ = try await runtime.register(id: id)
        return true
    } catch {
        return false
    }
}

// ==========================================================================
// MARK: - Run
// ==========================================================================

@main
struct Main {
    static func main() async {
        let iterations = 1000

        var staleA = 0
        var staleB = 0
        var staleC = 0

        for i in 0..<iterations {
            let loop = Loop()
            loop.start()
            let runtime = Runtime(loop: loop)
            if await scenarioA(loop: loop, runtime: runtime, id: i) {
                staleA += 1
            }
        }
        for i in 0..<iterations {
            let loop = Loop()
            loop.start()
            let runtime = Runtime(loop: loop)
            if await scenarioB(loop: loop, runtime: runtime, id: i) {
                staleB += 1
            }
        }
        for i in 0..<iterations {
            let loop = Loop()
            loop.start()
            let runtime = Runtime(loop: loop)
            if await scenarioC(loop: loop, runtime: runtime, id: i) {
                staleC += 1
            }
        }

        print("\n=== RESULTS ===")
        print("Iterations per scenario: \(iterations)")
        print("Stale (Scenario A — single thread):       \(staleA)")
        print("Stale (Scenario B — child Task):          \(staleB)")
        print("Stale (Scenario C — detached Task):       \(staleC)")
        let total = staleA + staleB + staleC
        print(total > 0
              ? "REPRODUCED: \(total) stale reads across \(iterations * 3) trials"
              : "NOT REPRODUCED in this run")
    }
}
