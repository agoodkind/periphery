import SwiftParser
import SwiftSyntax

public final class GeneratedStringSymbols: SyntaxVisitor {
    public private(set) var keysByLine: [Int: String] = [:]
    private let converter: SourceLocationConverter

    private init(tree: SourceFileSyntax) {
        converter = SourceLocationConverter(fileName: "", tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    public static func keys(in source: String) -> [Int: String] {
        let tree = Parser.parse(source: source)
        let visitor = GeneratedStringSymbols(tree: tree)
        visitor.walk(tree)
        return visitor.keysByLine
    }

    override public func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.modifiers.contains(where: { $0.name.text == "static" }) else { return .skipChildren }

        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let block = binding.accessorBlock,
                  let key = key(in: block)
            else { continue }

            let line = converter.location(for: identifier.identifier.positionAfterSkippingLeadingTrivia).line
            keysByLine[line] = key
        }
        return .skipChildren
    }

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.modifiers.contains(where: { $0.name.text == "static" }),
              let body = node.body,
              let key = key(in: body)
        else { return .skipChildren }

        let line = converter.location(for: node.name.positionAfterSkippingLeadingTrivia).line
        keysByLine[line] = key
        return .skipChildren
    }

    private func key(in node: some SyntaxProtocol) -> String? {
        let visitor = KeyVisitor(viewMode: .sourceAccurate)
        visitor.walk(node)
        guard visitor.keys.count == 1 else { return nil }

        return visitor.keys.first
    }
}

private final class KeyVisitor: SyntaxVisitor {
    var keys: Set<String> = []

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let name = node.calledExpression.as(DeclReferenceExprSyntax.self),
              name.baseName.text == "LocalizedStringResource",
              let argument = node.arguments.first,
              argument.label == nil,
              let literal = argument.expression.as(StringLiteralExprSyntax.self),
              let key = literal.representedLiteralValue
        else { return .visitChildren }

        keys.insert(key)
        return .skipChildren
    }
}
