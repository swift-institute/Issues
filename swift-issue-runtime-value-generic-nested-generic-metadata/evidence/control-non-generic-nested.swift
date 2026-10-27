enum Link<let N: Int> {}

extension Link {
    struct Node {
        var element: Int
    }
}

print(_typeName(Link<1>.Node.self))
