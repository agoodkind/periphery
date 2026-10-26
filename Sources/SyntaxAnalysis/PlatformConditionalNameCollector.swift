import Foundation
import SwiftSyntax

/// Collects the identifiers written inside `#if` blocks conditioned on the target platform
/// (`os()`, `targetEnvironment()`, `arch()`, `canImport()`).
///
/// The index store only contains the code of the compilation condition that was built, so references
/// made from the inactive branches of these blocks are invisible to the indexer. Syntax trees contain
/// every branch, which allows us to know which names are possibly referenced from another platform.
public final class PlatformConditionalNameCollector: SyntaxVisitor {
    private static let platformConditions: Set<String> = ["os", "targetEnvironment", "arch", "canImport"]

    public private(set) var names: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    public static func collect(from syntax: SourceFileSyntax) -> Set<String> {
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

            for token in elements.tokens(viewMode: .sourceAccurate) {
                if case .identifier = token.tokenKind {
                    names.insert(token.identifier?.name ?? token.text)
                }
            }
        }

        return .skipChildren
    }

    // MARK: - Private

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
