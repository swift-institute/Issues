struct CapturedSendable: Sendable {
    let payload: any Sendable
    init<V: Sendable>(_ value: V) { self.payload = value }
}

struct CapturedStore {
    var slots: [CapturedSendable] = []
    mutating func insert<V: Sendable>(_ value: V) -> Int {
        slots.append(CapturedSendable(value))
        return slots.count - 1
    }
}

enum TestError: Error, Sendable { case bad }

func triggerCrash() {
    var store = CapturedStore()
    let closure: @Sendable (Int) throws(TestError) -> Int = { (x: Int) throws(TestError) in
        guard x >= 0 else { throw .bad }
        return x * 2
    }
    let id = store.insert(closure)
    _ = id
}

triggerCrash()
