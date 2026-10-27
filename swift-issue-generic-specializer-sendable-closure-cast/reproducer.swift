struct CapturedSendable: Sendable {
    let payload: any Sendable
    init<V: Sendable>(_ value: V) { self.payload = value }
}

struct CapturedID<Value: Sendable>: Sendable {
    let index: Int
}

struct CapturedStore {
    var slots: [CapturedSendable] = []
    mutating func insert<Value: Sendable>(_ value: Value) -> CapturedID<Value> {
        slots.append(CapturedSendable(value))
        return CapturedID(index: slots.count - 1)
    }
}

func triggerCrash() {
    var store = CapturedStore()
    let id = store.insert({ (x: Int) in x * 2 } as @Sendable (Int) -> Int)
    _ = id
}

triggerCrash()
