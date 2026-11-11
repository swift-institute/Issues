protocol Q { associatedtype Element }
protocol R { associatedtype Element }
struct S<Element> {}
extension S: R where Element == Int {}
extension S: Q {}
let x: S<Int>.Element = 0
