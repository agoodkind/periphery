import Configuration
import Foundation
import Shared

final class UsedDeclarationMarker: SourceGraphMutator {
    private static let swiftUIViewUsr = "s:7SwiftUI4ViewP"

    private let graph: SourceGraph

    required init(graph: SourceGraph, configuration _: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
    }

    func mutate() {
        removeErroneousProtocolReferences()
        markUsed(graph.retainedDeclarations)

        graph.rootReferences.forEach { markUsed(declarationsReferenced(by: $0)) }
        markLivePreviewExpansionsUsed()

        ignoreUnusedDescendents(in: graph.rootDeclarations,
                                unusedDeclarations: graph.unusedDeclarations)
    }

    // MARK: - Private

    /// Removes references from protocol member decls to conforming decls that have a dereferenced ancestor.
    private func removeErroneousProtocolReferences() {
        // Evaluate ancestor dereference status from a stable pre-mutation snapshot to avoid
        // order-dependent behavior when iterating sets and removing references.
        let dereferencedDeclarations = graph.allDeclarations.filter {
            !(graph.isRetained($0) || graph.hasReferences(to: $0))
        }

        let dereferencedAncestors = Set(dereferencedDeclarations)
        var referencesToRemove = Set<Reference>()

        for protocolDecl in graph.declarations(ofKind: .protocol) {
            for memberDecl in protocolDecl.declarations {
                for relatedRef in memberDecl.related {
                    guard let relatedDecl = graph.declaration(withUsr: relatedRef.usr) else { continue }

                    let hasDereferencedAncestor = relatedDecl.ancestralDeclarations.contains {
                        dereferencedAncestors.contains($0)
                    }

                    if hasDereferencedAncestor {
                        referencesToRemove.insert(relatedRef)
                    }
                }
            }
        }

        for reference in referencesToRemove {
            graph.remove(reference)
        }
    }

    private func markUsed(_ declarations: Set<Declaration>) {
        for declaration in declarations {
            guard !graph.isUsed(declaration) else { continue }

            graph.markUsed(declaration)

            for ref in declaration.references {
                markUsed(declarationsReferenced(by: ref))
            }

            for ref in declaration.related {
                markUsed(declarationsReferenced(by: ref))
            }
        }
    }

    /// Marks used each `#Preview` expansion that previews a used SwiftUI view, along with the code
    /// it references. Previews that only reference unused code stay unused.
    private func markLivePreviewExpansionsUsed() {
        var pendingPreviews = graph.references(to: SwiftUIRetainer.previewRegistryUsr)
            .compactMap(\.parent)
            .filter { $0.isImplicit && !graph.isUsed($0) }
            .mapSet { $0 }

        while true {
            let livePreviews = pendingPreviews.filter(previewsUsedView)
            guard !livePreviews.isEmpty else { break }

            pendingPreviews.subtract(livePreviews)
            markUsed(livePreviews.flatMapSet { $0.descendentDeclarations.union([$0]) })
        }
    }

    private func previewsUsedView(_ preview: Declaration) -> Bool {
        ([preview] + preview.descendentDeclarations)
            .lazy
            .flatMap(\.references)
            .compactMap { self.graph.declaration(withUsr: $0.usr) }
            .contains { self.graph.isUsed($0) && self.isSwiftUIView($0) }
    }

    private func isSwiftUIView(_ declaration: Declaration) -> Bool {
        guard [.struct, .class, .enum].contains(declaration.kind) else { return false }

        return declaration.related.contains {
            $0.declarationKind == .protocol && $0.usr == Self.swiftUIViewUsr
        }
    }

    private func declarationsReferenced(by reference: Reference) -> Set<Declaration> {
        var declarations: Set<Declaration> = []

        if let declaration = graph.declaration(withUsr: reference.usr) {
            declarations.insert(declaration)
        }

        return declarations
    }

    private func ignoreUnusedDescendents(in decls: Set<Declaration>, unusedDeclarations: Set<Declaration>) {
        for decl in decls {
            guard !decl.declarations.isEmpty || !decl.unusedParameters.isEmpty
            else { continue }

            if unusedDeclarations.contains(decl) {
                decl.descendentDeclarations.forEach { graph.markIgnored($0) }
            } else {
                ignoreUnusedDescendents(in: decl.declarations,
                                        unusedDeclarations: unusedDeclarations)
            }
        }
    }
}
