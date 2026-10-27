import BugModule
@_spi(Syscall) import Kernel_Descriptor_Primitives

func run() async throws {
    for iteration in 0..<100 {
        let scope = try await IO.Event.Selector.Scope()
        let selector = scope.selector

        await scope.close()

        do throws(IO.Event.Failure) {
            try await selector.register(
                Kernel.Descriptor(_rawValue: -1),
                interest: Kernel.Event.Interest.read
            )
            print("BUG (\(iteration)): register should have thrown")
            fatalError()
        } catch {
            switch error {
            case .shutdownInProgress:
                break
            case .failure(let leaf):
                print("BUG (\(iteration)): .failure(\(leaf)) instead of .shutdownInProgress")
                // Don't fatalError — continue to show all iterations
                break
            case .cancellation, .timeout:
                print("BUG (\(iteration)): unexpected: \(error)")
                fatalError()
            }
        }
    }
    print("PASS: 100 iterations correct")
}

try await run()
