import Foundation
import SourceGraph
import SwiftSyntax

/// Collects the identifiers written inside `#if` blocks conditioned on the target platform
/// (`os()`, `targetEnvironment()`, `arch()`, `canImport()`).
///
/// The index store only contains the code of the compilation condition that was built, so references
/// made from the inactive branches of these blocks are invisible to the indexer. Syntax trees contain
/// every branch, which allows us to know which names are possibly referenced from another platform.
///
/// The collector records a `PlatformConditionalNameUse` for each identifier, including the receiver name for member
/// uses such as `Receiver.name` or `Receiver().name`.
/// For a receiver variable with an explicit type annotation in the same `#if` clause, it records the type name instead.
/// Any other use sets `hasUnknownReceiver`.
public final class PlatformConditionalNameCollector: SyntaxVisitor {
    private static let platformConditions: Set<String> = ["os", "targetEnvironment", "arch", "canImport"]

    public private(set) var names: [String: PlatformConditionalNameUse] = [:]

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    public static func collect(from syntax: SourceFileSyntax) -> [String: PlatformConditionalNameUse] {
        let collector = PlatformConditionalNameCollector()
        collector.walk(syntax)
        return collector.names
    }

    override public func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.clauses.contains(where: { isPlatformCondition($0.condition) }) else {
            return .visitChildren
        }

        // The `#else` clause has no condition of its own, so the whole block is collected.
        for clause in node.clauses {
            guard let elements = clause.elements else { continue }

            let annotatedTypeNames = AnnotatedTypeNameCollector.collect(in: elements)

            for token in elements.tokens(viewMode: .sourceAccurate) {
                guard case .identifier = token.tokenKind else { continue }

                let name = token.identifier?.name ?? token.text
                var use = names[name, default: PlatformConditionalNameUse()]

                if let receiverName = receiverName(of: token) {
                    use.receiverNames.insert(annotatedTypeNames[receiverName] ?? receiverName)
                } else {
                    use.hasUnknownReceiver = true
                }

                names[name] = use
            }
        }

        return .skipChildren
    }

    // MARK: - Private

    /// The function returns the name before the dot when the token is the member name in `Base.member` or
    /// `Base().member`.
    /// It returns `nil` for every other position, including implicit member expressions such as `.member`.
    private func receiverName(of token: TokenSyntax) -> String? {
        guard let reference = token.parent?.as(DeclReferenceExprSyntax.self),
              let memberAccess = reference.parent?.as(MemberAccessExprSyntax.self),
              memberAccess.declName.id == reference.id,
              let base = memberAccess.base
        else { return nil }

        if let baseReference = base.as(DeclReferenceExprSyntax.self) {
            return baseReference.baseName.identifier?.name ?? baseReference.baseName.text
        }

        if let call = base.as(FunctionCallExprSyntax.self),
           let callee = call.calledExpression.as(DeclReferenceExprSyntax.self)
        {
            return callee.baseName.identifier?.name ?? callee.baseName.text
        }

        return nil
    }

    private func isPlatformCondition(_ condition: ExprSyntax?) -> Bool {
        guard let condition else { return false }

        return condition.tokens(viewMode: .sourceAccurate).contains {
            if case .identifier = $0.tokenKind {
                Self.platformConditions.contains($0.text)
            } else {
                false
            }
        }
    }
}

/// The visitor maps variables with explicit type annotations inside one `#if` clause to the last component of their
/// type name.
/// Both `let name: TypeName` and `let name: Module.TypeName` map `name` to `TypeName`.
private final class AnnotatedTypeNameCollector: SyntaxVisitor {
    private var typeNamesByVariableName: [String: String] = [:]

    static func collect(in node: some SyntaxProtocol) -> [String: String] {
        let collector = AnnotatedTypeNameCollector(viewMode: .sourceAccurate)
        collector.walk(node)
        return collector.typeNamesByVariableName
    }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        guard let pattern = node.pattern.as(IdentifierPatternSyntax.self),
              let type = node.typeAnnotation?.type
        else { return .visitChildren }

        let typeName: String? = if let identifierType = type.as(IdentifierTypeSyntax.self) {
            identifierType.name.text
        } else if let memberType = type.as(MemberTypeSyntax.self) {
            memberType.name.text
        } else {
            nil
        }

        if let typeName {
            typeNamesByVariableName[pattern.identifier.text] = typeName
        }

        return .visitChildren
    }
}
