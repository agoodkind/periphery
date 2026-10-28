import Configuration
import Foundation
import Shared

/// Retains static methods used by the Result Builder language feature.
final class ResultBuilderRetainer: SourceGraphMutator {
    private let graph: SourceGraph
    // Names the compiler calls implicitly (SE-0289, SE-0348). buildBlock may have any arity.
    private let resultBuilderMethods = Set<String>([
        "buildExpression(_:)",
        "buildOptional(_:)",
        "buildEither(first:)",
        "buildEither(second:)",
        "buildArray(_:)",
        "buildFinalResult(_:)",
        "buildLimitedAvailability(_:)",
        "buildPartialBlock(first:)",
        "buildPartialBlock(accumulated:next:)",
    ])

    required init(graph: SourceGraph, configuration _: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
    }

    func mutate() {
        for decl in graph.declarations(ofKinds: Declaration.Kind.toplevelAttributableKind) where decl.attributes.contains(where: { $0.name == "resultBuilder" }) {
            for childDecl in decl.declarations {
                if isResultBuilderMethod(childDecl.name) {
                    graph.markRetained(childDecl)
                }
            }
        }
    }

    private func isResultBuilderMethod(_ name: String) -> Bool {
        resultBuilderMethods.contains(name) || name.hasPrefix("buildBlock(")
    }
}
