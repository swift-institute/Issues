struct One: Sendable {
    typealias Value = String
    let body: @Sendable (sending () -> Value) async -> Void

    func resume(returning value: sending Value) async {
        await body { value }
    }
}

@main
struct App {
    static func main() async {
        let one = One { @Sendable (thunk: sending () -> String) async in
            print(thunk())
        }
        await one.resume(returning: "hello")
    }
}
