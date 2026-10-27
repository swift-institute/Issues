enum Link<N> {}

extension Link {
    struct Node<Element> {
        var element: Element
    }
}

print(_typeName(Link<Int>.Node<Int>.self))
