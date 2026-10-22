import SwiftParser
import SwiftSyntax

/// One proposed simplification of a source file: replace a byte range.
public struct Edit: Hashable, Sendable {
    public var kind: String
    public var start: Int
    public var end: Int
    public var replacement: String
    /// Identifies the edit independently of its position, so a rejected edit
    /// is not retried within the same pass after earlier text moved.
    public var key: String

    public var removedBytes: Int { (end - start) - replacement.utf8.count }

    public func apply(to source: [UInt8]) -> [UInt8] {
        Array(source[..<start]) + Array(replacement.utf8) + Array(source[end...])
    }
}

extension Edit {
    /// Every candidate edit for `source`, largest reduction first.
    public static func candidates(in source: String) -> [Edit] {
        let tree = Parser.parse(source: source)
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(tree)
        var seen = Set<Edit>()
        return collector.edits
            .filter { $0.removedBytes > 0 && seen.insert($0).inserted }
            .sorted { $0.removedBytes != $1.removedBytes ? $0.removedBytes > $1.removedBytes : $0.start < $1.start }
    }

    /// The source with every comment removed and runs of blank lines collapsed.
    public static func stripped(_ source: String) -> String {
        let tree = Parser.parse(source: source)
        let text = CommentStripper(viewMode: .sourceAccurate).rewrite(tree).description
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var kept = String(line)
            while kept.last?.isWhitespace == true { kept.removeLast() }
            if kept.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(kept)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }
}

final class CommentStripper: SyntaxRewriter {
    override func visit(_ token: TokenSyntax) -> TokenSyntax {
        token
            .with(\.leadingTrivia, Self.strip(token.leadingTrivia))
            .with(\.trailingTrivia, Self.strip(token.trailingTrivia))
    }

    static func strip(_ trivia: Trivia) -> Trivia {
        Trivia(pieces: trivia.pieces.filter {
            switch $0 {
            case .lineComment, .blockComment, .docLineComment, .docBlockComment: false
            default: true
            }
        })
    }
}

final class Collector: SyntaxVisitor {
    var edits: [Edit] = []

    func add(_ kind: String, _ node: some SyntaxProtocol, _ replacement: String = "", trivia: Bool = true) {
        let start = trivia ? node.position.utf8Offset : node.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = trivia ? node.endPosition.utf8Offset : node.endPositionBeforeTrailingTrivia.utf8Offset
        let text = node.trimmedDescription
        edits.append(Edit(kind: kind, start: start, end: end, replacement: replacement, key: "\(kind)|\(replacement)|\(text)"))
    }

    /// Removes an element of a comma-separated list, along with the comma
    /// before it when it is the last element.
    func addListElement<Element: SyntaxProtocol>(_ kind: String, _ element: Element, in list: [Element], trailingComma: (Element) -> TokenSyntax?) {
        guard let index = list.firstIndex(where: { $0.id == element.id }) else { return }
        if index == list.count - 1, index > 0, let comma = trailingComma(list[index - 1]) {
            let start = comma.position.utf8Offset
            let end = element.endPositionBeforeTrailingTrivia.utf8Offset
            edits.append(Edit(kind: kind, start: start, end: end, replacement: "", key: "\(kind)||\(element.trimmedDescription)"))
        } else {
            add(kind, element)
        }
    }

    // Statements and top-level declarations.
    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        add("remove statement or declaration", node)
        if let expression = node.item.as(ExpressionStmtSyntax.self)?.expression ?? node.item.as(ExprSyntax.self) {
            // `try f()` → `f()`, `await f()` → `f()`
            if let tryExpr = expression.as(TryExprSyntax.self) {
                add("drop try", tryExpr, tryExpr.expression.trimmedDescription, trivia: false)
            }
            if let awaitExpr = expression.as(AwaitExprSyntax.self) {
                add("drop await", awaitExpr, awaitExpr.expression.trimmedDescription, trivia: false)
            }
        }
        return .visitChildren
    }

    // Members of types and extensions.
    override func visit(_ node: MemberBlockItemSyntax) -> SyntaxVisitorContinueKind {
        add("remove member", node)
        return .visitChildren
    }

    // Bodies: empty first, then a trap, which keeps non-Void returns valid.
    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        let isBody = node.parent?.is(FunctionDeclSyntax.self) == true
            || node.parent?.is(InitializerDeclSyntax.self) == true
            || node.parent?.is(DeinitializerDeclSyntax.self) == true
            || node.parent?.is(AccessorDeclSyntax.self) == true
        if isBody, !node.statements.isEmpty {
            add("empty body", node, "{}", trivia: false)
            add("trap body", node, "{ fatalError() }", trivia: false)
        }
        // A `do` block or an `if` branch replaced by its own statements.
        if node.parent?.is(DoStmtSyntax.self) == true, let doStmt = node.parent?.as(DoStmtSyntax.self) {
            add("inline do", doStmt, node.statements.trimmedDescription, trivia: false)
        }
        return .visitChildren
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        if case .getter(let statements) = node.accessors, !statements.isEmpty {
            add("trap getter", node, "{ fatalError() }", trivia: false)
        }
        return .visitChildren
    }

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        if let elseBody = node.elseBody, let elseKeyword = node.elseKeyword {
            edits.append(Edit(
                kind: "drop else",
                start: elseKeyword.position.utf8Offset,
                end: elseBody.endPositionBeforeTrailingTrivia.utf8Offset,
                replacement: "",
                key: "drop else||\(elseBody.trimmedDescription)"
            ))
        }
        add("inline if", node, node.body.statements.trimmedDescription, trivia: false)
        return .visitChildren
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        add("remove guard", node)
        return .visitChildren
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        add("remove catch", node)
        return .visitChildren
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        add("remove switch case", node)
        return .visitChildren
    }

    // `#if` blocks: keep one clause's contents, or drop one clause, or drop all.
    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        for clause in node.clauses {
            let contents = clause.elements.map { $0.trimmedDescription } ?? ""
            add("keep #if clause", node, contents, trivia: false)
            if node.clauses.count > 1 { add("remove #if clause", clause) }
        }
        add("remove #if", node)
        return .visitChildren
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        add("remove attribute", node)
        return .visitChildren
    }

    override func visit(_ node: DeclModifierSyntax) -> SyntaxVisitorContinueKind {
        add("remove modifier", node)
        return .visitChildren
    }

    override func visit(_ node: InheritanceClauseSyntax) -> SyntaxVisitorContinueKind {
        add("remove inheritance clause", node)
        let list = Array(node.inheritedTypes)
        for element in list { addListElement("remove conformance", element, in: list) { $0.trailingComma } }
        return .visitChildren
    }

    override func visit(_ node: GenericWhereClauseSyntax) -> SyntaxVisitorContinueKind {
        add("remove where clause", node)
        let list = Array(node.requirements)
        for element in list { addListElement("remove requirement", element, in: list) { $0.trailingComma } }
        return .visitChildren
    }

    override func visit(_ node: GenericParameterClauseSyntax) -> SyntaxVisitorContinueKind {
        add("remove generic parameters", node)
        let list = Array(node.parameters)
        for element in list { addListElement("remove generic parameter", element, in: list) { $0.trailingComma } }
        return .visitChildren
    }

    override func visit(_ node: FunctionParameterClauseSyntax) -> SyntaxVisitorContinueKind {
        let list = Array(node.parameters)
        for element in list {
            addListElement("remove parameter", element, in: list) { $0.trailingComma }
            if let defaultValue = element.defaultValue { add("remove default value", defaultValue) }
        }
        return .visitChildren
    }

    override func visit(_ node: LabeledExprListSyntax) -> SyntaxVisitorContinueKind {
        let list = Array(node)
        for element in list { addListElement("remove argument", element, in: list) { $0.trailingComma } }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let trailing = node.trailingClosure { add("remove trailing closure", trailing) }
        return .visitChildren
    }

    override func visit(_ node: EnumCaseElementListSyntax) -> SyntaxVisitorContinueKind {
        let list = Array(node)
        if list.count > 1 {
            for element in list { addListElement("remove enum case", element, in: list) { $0.trailingComma } }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionEffectSpecifiersSyntax) -> SyntaxVisitorContinueKind {
        if let throwsClause = node.throwsClause { add("remove throws", throwsClause) }
        if let asyncSpecifier = node.asyncSpecifier { add("remove async", asyncSpecifier) }
        return .visitChildren
    }

    override func visit(_ node: ReturnClauseSyntax) -> SyntaxVisitorContinueKind {
        add("remove return type", node)
        return .visitChildren
    }

    override func visit(_ node: InitializerClauseSyntax) -> SyntaxVisitorContinueKind {
        if node.parent?.is(PatternBindingSyntax.self) == true {
            add("trap initial value", node.value, "fatalError()", trivia: false)
        }
        return .visitChildren
    }
}
