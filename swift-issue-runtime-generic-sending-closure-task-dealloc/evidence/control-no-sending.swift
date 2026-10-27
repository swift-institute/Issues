struct One<Value: Sendable>: Sendable {
    let body: @Sendable (() -> Value) async -> Void

    func resume(returning value: sending Value) async {
        await body { value }
    }
}

@main
struct App {
    static func main() async {
        let one = One<String> { @Sendable (thunk: () -> String) async in
            print(thunk())
        }
        await one.resume(returning: "hello")
    }
}
