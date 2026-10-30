import AEXML
import Foundation
import SourceGraph
import SystemPackage

final class XCDataModelParser {
    private let path: FilePath

    required init(path: FilePath) {
        self.path = path
    }

    func parse() throws -> [AssetReference] {
        if path.lastComponent?.string == "contents" {
            return try parseContents(at: path)
        }

        return try FileManager.default.contentsOfDirectory(atPath: path.string).flatMap { subPath -> [AssetReference] in
            let modelPath = path.appending(subPath)
            guard modelPath.extension == "xcdatamodel" else { return [] }

            return try parseContents(at: modelPath.appending("contents"))
        }
    }

    // MARK: - Private

    private func parseContents(at contentsPath: FilePath) throws -> [AssetReference] {
        guard let data = FileManager.default.contents(atPath: contentsPath.string) else { return [] }

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
