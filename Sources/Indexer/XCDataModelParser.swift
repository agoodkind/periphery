import AEXML
import Foundation
import SourceGraph
import SystemPackage

final class XCDataModelParser {
    private let input: ModelInput

    required init(input: ModelInput) {
        self.input = input
    }

    func parse() throws -> [AssetReference] {
        switch input {
        case let .file(path):
            try parseContents(at: path)
        case let .directory(path):
            try FileManager.default.contentsOfDirectory(atPath: path.string).flatMap { subPath -> [AssetReference] in
                let modelPath = path.appending(subPath)
                guard modelPath.extension?.lowercased() == "xcdatamodel" else { return [] }

                return try parseContents(at: modelPath.appending("contents"))
            }
        }
    }

    // MARK: - Private

    private func parseContents(at contentsPath: FilePath) throws -> [AssetReference] {
        let data = try Data(contentsOf: URL(fileURLWithPath: contentsPath.string))

        let structure = try AEXMLDocument(xml: data)
        return references(from: structure.root).map {
            AssetReference(absoluteName: $0, source: .xcDataModel)
        }
    }

    private func references(from element: AEXMLElement) -> [String] {
        var names: [String] = []

        for child in element.children {
            if let name = child.attributes["customClassName"] {
                names.append(name)
            }

            names += references(from: child)
        }

        return names
    }
}
