import AEXML
import Foundation
import SourceGraph
import SystemPackage

final class XCMappingModelParser {
    private let path: FilePath

    required init(input: ModelInput) {
        switch input {
        case let .file(path): self.path = path
        case let .directory(path): self.path = path.appending("xcmapping.xml")
        }
    }

    func parse() throws -> [AssetReference] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path.string))

        let structure = try AEXMLDocument(xml: data)
        return references(from: structure.root).map {
            AssetReference(absoluteName: $0, source: .xcMappingModel)
        }
    }

    // MARK: - Private

    private func references(from element: AEXMLElement) -> [String] {
        var names: [String] = []

        for child in element.children {
            if child.attributes["name"] == "migrationpolicyclassname" {
                names.append(child.string)
            }

            names += references(from: child)
        }

        return names
    }
}
