import Configuration
import Foundation
import Shared

final class SwiftUIRetainer: SourceGraphMutator {
    private let graph: SourceGraph
    private let configuration: Configuration
    private static let specialProtocolNames = ["LibraryContentProvider"]
    private static let applicationDelegateAdaptorStructNames = ["UIApplicationDelegateAdaptor", "NSApplicationDelegateAdaptor"]

    required init(graph: SourceGraph, configuration: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
        self.configuration = configuration
    }

    func mutate() {
        associateStatePropertyReads()
        retainSpecialProtocolConformances()
        retainApplicationDelegateAdaptors()
        unretainPreviewMacroExpansions()
    }

    // MARK: - Private

    private func associateStatePropertyReads() {
        for reference in graph.allReferences where reference.isExplicitRead {
            guard let generated = graph.declaration(withUsr: reference.usr),
                  generated.isImplicit,
                  generated.kind == .varInstance
            else { continue }
            guard generated.name.hasPrefix("$") || generated.name.hasPrefix("_") else { continue }
            guard let owner = generated.parent else { continue }

            let propertyName = String(generated.name.dropFirst())
            let properties = owner.declarations.filter {
                !$0.isImplicit && $0.kind == .varInstance && $0.name == propertyName &&
                    $0.references.contains(where: { $0.usr == "s:7SwiftUI5Stateyycfm" })
            }
            guard properties.count == 1, let property = properties.first else { continue }

            // Preserve the source caller. Implicit state accessors are retained independently.
            for usr in property.usrs {
                let read = Reference(
                    name: property.name,
                    kind: .normal,
                    declarationKind: property.kind,
                    usr: usr,
                    location: reference.location
                )
                read.parent = reference.parent
                if let parent = read.parent {
                    graph.add(read, from: parent)
                } else {
                    graph.addRootReference(read)
                }
            }
        }
    }

    private func retainSpecialProtocolConformances() {
        var names = Self.specialProtocolNames

        if configuration.retainSwiftUIPreviews {
            names.append("PreviewProvider")
        }

        graph
            .declarations(ofKinds: [.class, .struct, .enum])
            .lazy
            .filter {
                $0.related.contains {
                    self.graph.isExternal($0) && $0.declarationKind == .protocol && names.contains($0.name)
                }
            }
            .forEach { graph.markRetained($0) }
    }

    private func retainApplicationDelegateAdaptors() {
        graph
            .mainAttributedDeclarations
            .lazy
            .flatMap(\.declarations)
            .filter { $0.kind == .varInstance }
            .filter {
                $0.references.contains {
                    ($0.declarationKind == .struct || $0.declarationKind == .enum) && Self.applicationDelegateAdaptorStructNames.contains($0.name)
                }
            }
            .forEach { graph.markRetained($0) }
    }

    private func unretainPreviewMacroExpansions() {
        guard !configuration.retainSwiftUIPreviews else { return }

        let previewRegistryUsr = "s:21DeveloperToolsSupport15PreviewRegistryP"
        let macroReferences = graph.references(to: previewRegistryUsr)
        guard !macroReferences.isEmpty else { return }

        for reference in macroReferences {
            if let parent = reference.parent, parent.isImplicit {
                graph.unmarkRetained(parent)

                for decl in parent.declarations {
                    graph.unmarkRetained(decl)
                }
            }
        }
    }
}
