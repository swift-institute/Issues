protocol Parsing<Input, Output>: ~Copyable {
    associatedtype Input: ~Copyable
    associatedtype Output: ~Copyable
}
protocol Coding: Parsing, ~Copyable where Input: ~Copyable, Output: ~Copyable {}
protocol Symbol { associatedtype Input: ~Copyable }
struct App<Index: Symbol, Input: ~Copyable>: ~Copyable where Index.Input == Input {}
extension App where Input: ~Copyable {
    struct Coder<Inner: Coding>
    where Inner.Input: ~Copyable, Inner.Output: ~Copyable, Inner.Output == Input {}
}
extension App.Coder: Parsing
where Input: ~Copyable, Inner.Input: ~Copyable, Inner.Output: ~Copyable {
    typealias Input = Inner.Input
    typealias Output = App<Index, Inner.Output>
}
extension App.Coder: Coding
where Input: ~Copyable, Inner.Input: ~Copyable, Inner.Output: ~Copyable {}
struct Case<Input: ~Copyable, Source: ~Copyable, Focus: ~Copyable, Content: Coding & ~Copyable>: ~Copyable
where Content.Input == Input, Content.Output == Focus {}
extension Case where Input: ~Copyable, Source: ~Copyable, Focus: ~Copyable {
    init<Index: Symbol, Inner: Coding>(dummy: Void)
    where
        Focus == App<Index, Index.Input>,
        Content == App<Index, Index.Input>.Coder<Inner>,
        Inner.Input == Input,
        Inner.Input: ~Copyable,
        Inner.Output == Index.Input,
        Index.Input: ~Copyable,
        Inner.Output: ~Copyable
    { fatalError() }
}
