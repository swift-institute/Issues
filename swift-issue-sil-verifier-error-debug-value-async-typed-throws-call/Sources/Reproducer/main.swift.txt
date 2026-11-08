import BugLib

func run() async throws {
    for i in 0..<100 {
        let scope = Scope()
        let sel = scope.selector
        await scope.close()

        do throws(Err) {
            try await sel.register()
            fatalError("should have thrown")
        } catch {
            if error.id != 1 {
                print("BUG (\(i)): got id=\(error.id), expected 1")
            }
        }
    }
    print("PASS")
}

try await run()
