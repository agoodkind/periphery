import Configuration
import Foundation
import Indexer
import IndexStore
import Logger
import Shared
import SourceGraph
import SystemPackage

public final class SPMProjectDriver {
    private let pkg: SPM.Package
    private let configuration: Configuration
    private let logger: Logger

    public convenience init(configuration: Configuration, shell: Shell, logger: Logger) throws {
        if !configuration.schemes.isEmpty {
            throw PeripheryError.usageError("The --schemes option has no effect with Swift Package Manager projects.")
        }

        let pkg = SPM.Package(configuration: configuration, shell: shell, logger: logger)
        self.init(pkg: pkg, configuration: configuration, logger: logger)
    }

    init(pkg: SPM.Package, configuration: Configuration, logger: Logger) {
        self.pkg = pkg
        self.configuration = configuration
        self.logger = logger
    }
}

extension SPMProjectDriver: ProjectDriver {
    public func build() throws {
        if !configuration.skipBuild {
            if configuration.cleanBuild {
                try pkg.clean()
            }

            if configuration.outputFormat.supportsAuxiliaryOutput {
                let asterisk = logger.colorize("*", .boldGreen)
                logger.info("\(asterisk) Building...")
            }

            try pkg.build(additionalArguments: configuration.buildArguments)
        }
    }

    public func plan(logger: ContextualLogger) throws -> IndexPlan {
        let indexStorePaths: Set<FilePath> = if !configuration.indexStorePath.isEmpty {
            Set(configuration.indexStorePath)
        } else {
            try [pkg.indexStorePath(additionalArguments: configuration.buildArguments)]
        }

        // Load package description once and reuse it
        let description = try pkg.load()

        let excludedTestTargets = configuration.excludeTests ? testTargetNames(from: description) : []
        let collector = SourceFileCollector(
            indexStorePaths: indexStorePaths,
            excludedTestTargets: excludedTestTargets,
            logger: logger,
            configuration: configuration
        )
        let sourceFiles = try collector.collect()
        let xibPaths = projectFiles(of: .interfaceBuilder, from: description)
        let xcDataModelPaths = projectFiles(of: .xcDataModel, from: description)
        let xcStringsPaths = projectFilesByModule(of: .xcStrings, from: description)

        return IndexPlan(
            sourceFiles: sourceFiles,
            xibPaths: xibPaths,
            xcDataModelPaths: xcDataModelPaths,
            xcStringsPaths: xcStringsPaths
        )
    }

    // MARK: - Private

    private func testTargetNames(from description: PackageDescription) -> Set<String> {
        description.targets.filter(\.isTestTarget).mapSet(\.name)
    }

    private func projectFiles(of kind: ProjectFileKind, from description: PackageDescription) -> Set<FilePath> {
        Set(projectFilesByModule(of: kind, from: description).keys)
    }

    /// The function maps each project file of the requested kind to the modules of targets that contain it.
    /// A target contains files under its directory outside nested target directories, plus files its `resources` list
    /// declares.
    /// The function uses each target's `c99name` from `swift package describe` as its module name.
    private func projectFilesByModule(of kind: ProjectFileKind, from description: PackageDescription) -> [FilePath: Set<String>] {
        var filesByModule: [FilePath: Set<String>] = [:]

        for target in description.targets {
            let moduleName = target.c99name ?? target.name

            for file in projectFiles(of: kind, in: target, from: description) {
                filesByModule[file, default: []].insert(moduleName)
            }
        }

        return filesByModule
    }

    private func projectFiles(of kind: ProjectFileKind, in target: Target, from description: PackageDescription) -> Set<FilePath> {
        var files: Set<FilePath> = []
        let extensions = kind.extensions
        let targetPath = pkg.path.appending(target.path).lexicallyNormalized()
        let nestedTargetPaths = description.targets.compactMap { otherTarget -> FilePath? in
            let otherPath = pkg.path.appending(otherTarget.path).lexicallyNormalized()
            return otherPath != targetPath && otherPath.starts(with: targetPath) ? otherPath : nil
        }

        // SwiftPM processes Interface Builder files and Core Data models implicitly, without a `resources:` declaration,
        // and `swift package describe` only lists the declared resources.
        var nestedProjectDirectories: [FilePath: Bool] = [:]

        for ext in extensions {
            let globbedFiles = FilePath.glob("\(targetPath.string)/**/*.\(ext)")

            for file in globbedFiles where !nestedTargetPaths.contains(where: { file.starts(with: $0) }) {
                let relativeComponents = file.components.dropFirst(targetPath.components.count)
                guard !relativeComponents.contains(where: { $0.string.hasPrefix(".") }) else { continue }

                if !isInsideNestedProject(file, under: targetPath, cache: &nestedProjectDirectories) {
                    files.insert(file)
                }
            }
        }

        for resource in target.resources ?? [] {
            // Resource.path is always a single file path
            let resourceFilePath = FilePath(resource.path)
            let resourcePath: FilePath = resourceFilePath.isAbsolute
                ? resourceFilePath
                : targetPath.appending(resource.path)

            // Check if the resource path exists and has an extension of this kind
            guard resourcePath.exists else { continue }
            guard let ext = resourcePath.extension?.lowercased(), extensions.contains(ext) else { continue }

            files.insert(resourcePath.lexicallyNormalized())
        }

        return files
    }

    /// The function checks each directory between `file` and `targetPath`, excluding `targetPath` itself.
    /// It returns `true` when a directory contains a `Package.swift` file, an `.xcodeproj` bundle, or an
    /// `.xcworkspace` bundle.
    /// That directory is the root of a separate project, such as a test fixture. Its files do not belong to the target.
    /// The function stores the result for each directory checked in `cache`.
    private func isInsideNestedProject(_ file: FilePath, under targetPath: FilePath, cache: inout [FilePath: Bool]) -> Bool {
        var directory = file.removingLastComponent()

        while directory != targetPath, directory.starts(with: targetPath) {
            let isProjectDirectory: Bool

            if let cachedValue = cache[directory] {
                isProjectDirectory = cachedValue
            } else {
                let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.string)) ?? []
                isProjectDirectory = entries.contains { entry in
                    entry == "Package.swift" || entry.hasSuffix(".xcodeproj") || entry.hasSuffix(".xcworkspace")
                }
                cache[directory] = isProjectDirectory
            }

            if isProjectDirectory {
                return true
            }

            directory = directory.removingLastComponent()
        }

        return false
    }
}
