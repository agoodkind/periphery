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
