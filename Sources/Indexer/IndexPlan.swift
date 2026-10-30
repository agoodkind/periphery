import Foundation
import SourceGraph
import SystemPackage

public struct IndexPlan {
    public let sourceFiles: [SourceFile: [IndexUnit]]
    public let plistPaths: Set<FilePath>
    public let xibPaths: Set<FilePath>
    public let xcDataModelPaths: Set<FilePath>
    public let xcMappingModelPaths: Set<FilePath>
    /// The property maps String Catalogs to index to the modules of targets that contain them.
    /// An empty set means the driver could not determine target membership.
    public let xcStringsPaths: [FilePath: Set<String>]
    public let nonMainBundleCatalogs: Set<FilePath>

    public init(
        sourceFiles: [SourceFile: [IndexUnit]],
        plistPaths: Set<FilePath> = [],
        xibPaths: Set<FilePath> = [],
        xcDataModelPaths: Set<FilePath> = [],
        xcMappingModelPaths: Set<FilePath> = [],
        xcStringsPaths: [FilePath: Set<String>] = [:],
        nonMainBundleCatalogs: Set<FilePath> = []
    ) {
        self.sourceFiles = sourceFiles
        self.plistPaths = plistPaths
        self.xibPaths = xibPaths
        self.xcDataModelPaths = xcDataModelPaths
        self.xcMappingModelPaths = xcMappingModelPaths
        self.xcStringsPaths = xcStringsPaths
        self.nonMainBundleCatalogs = nonMainBundleCatalogs
    }
}

enum ModelInput {
    enum Kind {
        case data
        case mapping
    }

    enum ValidationError: Error, CustomStringConvertible {
        case invalidPath(FilePath)

        var description: String {
            switch self {
            case let .invalidPath(path): "Invalid model path: \(path.string)"
            }
        }
    }

    case directory(FilePath)
    case file(FilePath)

    init(path: FilePath, kind: Kind) throws {
        switch kind {
        case .data:
            if path.extension?.lowercased() == "xcdatamodeld" {
                self = .directory(path)
            } else if path.lastComponent?.string == "contents", path.removingLastComponent().extension?.lowercased() == "xcdatamodel" {
                self = .file(path)
            } else {
                throw ValidationError.invalidPath(path)
            }
        case .mapping:
            if path.extension?.lowercased() == "xcmappingmodel" {
                self = .directory(path)
            } else if path.lastComponent?.string == "xcmapping.xml", path.removingLastComponent().extension?.lowercased() == "xcmappingmodel" {
                self = .file(path)
            } else {
                throw ValidationError.invalidPath(path)
            }
        }
    }
}
