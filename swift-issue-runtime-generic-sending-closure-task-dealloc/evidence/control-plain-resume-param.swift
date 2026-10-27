struct One<Value: Sendable>: Sendable {
    let body: @Sendable (sending () -> Value) async -> Void

    func resume(returning value: Value) async {
        await body { value }
    }
}

@main
struct App {
    static func main() async {
        let one = One<String> { @Sendable (thunk: sending () -> String) async in
            print(thunk())
        }
        await one.resume(returning: "hello")
    }
}
