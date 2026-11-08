// MARK: - CopyToBorrowOptimization Miscompile on Actor Mutex<Token?> State
// Purpose: Standalone 87-line repro of a release-mode miscompile where
//          WMO + CopyToBorrowOptimization removes an accidental retain
//          barrier on actor state held in a Mutex<Token?> field. Reading
//          the optional via `take()` after `await scope.close()` returns
//          a stale Token in some iterations (~50/100 typical).
//
// Toolchain: Swift 6.3 (Xcode 26)
// Revalidated: Swift 6.3.1 (2026-04-17) — STILL PRESENT (BUG observed in
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL PRESENT
//          ~50/100 iterations on 6.3.1; final "PASS" line is the script's
//          end-marker, not a verdict — the BUG print lines confirm the
//          miscompile. See memory `swift-6.3-fix-status.md`).
// Platform: macOS 26 (arm64)
// Workaround: -sil-disable-pass=copy-to-borrow-optimization OR remove
//          Mutex<Token?> from IO.Event.Selector.Scope (commit 6dad19ba).

import Synchronization

public final class Loop: SerialExecutor, @unchecked Sendable {
    public init() {}

    public func enqueue(_ job: UnownedJob) {
        unsafe job.runSynchronously(on: asUnownedSerialExecutor())
    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        unsafe UnownedSerialExecutor(ordinary: self)
    }
}

public struct Err: Error {
    public let id: Int
    public init(_ id: Int) { self.id = id }
}

public actor Runtime {
    public let executor: Loop
    private var state: State = .running

    nonisolated public var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    public init(executor: Loop) { self.executor = executor }

    enum State { case running, shuttingDown }

    public func register() throws(Err) {
        guard state == .running else { throw Err(1) }
        throw Err(2)
    }

    public func shutdown() async {
        state = .shuttingDown
    }
}

public struct Selector: Sendable {
    public let runtime: Runtime
    public init(runtime: Runtime) { self.runtime = runtime }

    public func register() async throws(Err) {
        try await runtime.register()
    }
}

public struct Scope: ~Copyable {
    public let selector: Selector
    private let _token: Mutex<Bool>

    public init() {
        let executor = Loop()
        let runtime = Runtime(executor: executor)
        self.selector = Selector(runtime: runtime)
        self._token = Mutex(false)
    }

    public consuming func close() async {
        await selector.runtime.shutdown()
    }

}
