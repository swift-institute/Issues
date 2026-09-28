protocol P {}
protocol Q {}
extension Int: P, Q {}
func make<T>(_ value: T) -> Int { 0 }
func make<each T>(_ value: (repeat each T)) -> Int { 0 }
func check(_ value: some P) {}
func check(_ value: some Q) {}
check(make(1))
