import Configuration
import Shared

/// Retains the generated conformance that checks SwiftProtobuf API compatibility.
final class ProtobufAPIVersionCheckRetainer: SourceGraphMutator {
    private let graph: SourceGraph
    private let protocolUsr = "s:13SwiftProtobuf0B15APIVersionCheckP"

    required init(graph: SourceGraph, configuration _: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
    }

    func mutate() {
        for declaration in graph.declarations(ofKind: .struct) {
            guard declaration.name == "_GeneratedWithProtocGenSwiftVersion",
                  declaration.accessibility.value == .fileprivate else { continue }
            guard declaration.declarations.contains(where: { $0.kind == .typealias && $0.name == "Version" }) else { continue }

            let conformances = graph.inheritedTypeReferences(of: declaration)
            guard conformances.contains(where: { $0.declarationKind == .protocol && $0.usr == protocolUsr }) else { continue }

            graph.markRetained(declaration)
        }
    }
}
