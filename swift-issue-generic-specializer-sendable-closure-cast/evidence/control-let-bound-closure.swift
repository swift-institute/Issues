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
    let closure: @Sendable (Int) -> Int = { (x: Int) in x * 2 }
    let id = store.insert(closure)
    _ = id
}

triggerCrash()
