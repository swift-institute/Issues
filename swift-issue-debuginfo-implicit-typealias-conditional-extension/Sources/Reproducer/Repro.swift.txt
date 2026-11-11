protocol P { }
protocol Q { associatedtype Element }
protocol R { associatedtype Element }
extension Shared: R where B: R {}
struct Shared<Element, B: P & Q> {}
extension Shared: Q {}
struct Col<Element>: P, Q, R {}
func probe() {
    let x: Shared<Int, Col<Int>>.Element = 0
}
