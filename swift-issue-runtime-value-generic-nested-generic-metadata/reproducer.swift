enum Link<let N: Int> {}

extension Link {
    struct Node<Element> {
        var element: Element
    }
}

print(_typeName(Link<1>.Node<Int>.self))
