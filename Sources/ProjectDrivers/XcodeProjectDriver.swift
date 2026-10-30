#if os(macOS)
    import Configuration
    import Foundation
    import Indexer
    import Logger
    import Shared
    import SourceGraph
    import SystemPackage
    import XcodeSupport

    public final class XcodeProjectDriver {
        private let logger: Logger
        private let configuration: Configuration
        private let xcodebuild: Xcodebuild
        private let project: XcodeProjectlike
        private let schemes: Set<String>

        public convenience init(
            projectPath: FilePath,
            configuration: Configuration,
            shell: Shell,
            logger: Logger
        ) throws {
            if configuration.outputFormat.supportsAuxiliaryOutput {
                let asterisk = logger.colorize("*", .boldGreen)
                logger.info("\(asterisk) Inspecting project...")
            }

            let xcodebuild = Xcodebuild(shell: shell, logger: logger)

            guard !configuration.schemes.isEmpty else {
                throw PeripheryError.usageError("The '--schemes' option is required.")
            }

            try xcodebuild.ensureConfigured()

            let project: XcodeProjectlike
            if projectPath.extension == "xcworkspace" {
                project = try XcodeWorkspace(
                    path: .makeAbsolute(projectPath),
                    xcodebuild: xcodebuild,
                    configuration: configuration,
                    logger: logger,
                    shell: shell
                )
            } else {
                var loadedProjectPaths: Set<FilePath> = []
                project = try XcodeProject(
                    path: .makeAbsolute(projectPath),
                    loadedProjectPaths: &loadedProjectPaths,
                    xcodebuild: xcodebuild,
                    shell: shell,
                    logger: logger
                )
            }

            let schemes: Set<String>

            if configuration.skipSchemesValidation {
                schemes = Set(configuration.schemes)
            } else {
                // Ensure schemes exist within the project
                if configuration.cleanBuild {
                    try xcodebuild.removeDerivedData(for: project, allSchemes: [])
                }
                schemes = try project.schemes(
                    additionalArguments: configuration.xcodeListArguments
                ).filter { configuration.schemes.contains($0) }
                let validSchemeNames = schemes.mapSet { $0 }

                if let scheme = Set(configuration.schemes).subtracting(validSchemeNames).first {
                    throw PeripheryError.invalidScheme(name: scheme, project: project.path.lastComponent?.string ?? "")
                }
            }

            self.init(
                logger: logger,
                configuration: configuration,
                xcodebuild: xcodebuild,
                project: project,
                schemes: schemes
            )
        }

        init(
            logger: Logger,
            configuration: Configuration,
            xcodebuild: Xcodebuild,
            project: XcodeProjectlike,
            schemes: Set<String>
        ) {
            self.logger = logger
            self.configuration = configuration
            self.xcodebuild = xcodebuild
            self.project = project
            self.schemes = schemes
        }
    }

    extension XcodeProjectDriver: ProjectDriver {
        public func build() throws {
            guard !configuration.skipBuild else { return }

            if configuration.cleanBuild {
                try xcodebuild.removeDerivedData(for: project, allSchemes: Array(schemes))
            }

            for scheme in schemes {
                if configuration.outputFormat.supportsAuxiliaryOutput {
                    let asterisk = logger.colorize("*", .boldGreen)
                    logger.info("\(asterisk) Building \(scheme)...")
                }

                try xcodebuild.build(project: project,
                                     scheme: scheme,
                                     allSchemes: Array(schemes),
                                     additionalArguments: configuration.buildArguments)
            }
        }

        public func plan(logger: ContextualLogger) throws -> IndexPlan {
            let indexStorePaths: Set<FilePath> = if !configuration.indexStorePath.isEmpty {
                Set(configuration.indexStorePath)
            } else {
                try [xcodebuild.indexStorePath(project: project, schemes: Array(schemes))]
            }

            let targets = project.targets
            try targets.forEach { try $0.identifyFiles() }
            let excludedTestTargets = configuration.excludeTests ? project.targets.filter(\.isTestTarget).mapSet(\.name) : []
            let collector = SourceFileCollector(
                indexStorePaths: indexStorePaths,
                excludedTestTargets: excludedTestTargets,
                logger: logger,
                configuration: configuration
            )
            let sourceFiles: [SourceFile: [IndexUnit]] = if configuration.disableUnusedLocalizedStringAnalysis {
                try collector.collect()
            } else {
                try collector.collectIncludingGeneratedStringSymbols()
            }
            let infoPlistPaths = targets.flatMapSet { $0.files(kind: .infoPlist) }
            let xibPaths = targets.flatMapSet { $0.files(kind: .interfaceBuilder) }
            let xcDataModelPaths = targets.flatMapSet { $0.files(kind: .xcDataModel) }
            let xcMappingModelPaths = targets.flatMapSet { $0.files(kind: .xcMappingModel) }
            let xcStringsPaths = catalogModules(targets: targets, sourceFiles: Set(sourceFiles.keys))

            return IndexPlan(
                sourceFiles: sourceFiles,
                plistPaths: infoPlistPaths,
                xibPaths: xibPaths,
                xcDataModelPaths: xcDataModelPaths,
                xcMappingModelPaths: xcMappingModelPaths,
                xcStringsPaths: xcStringsPaths
            )
        }

        // MARK: - Private

        /// The function maps each String Catalog in a target's resources build phase or synchronized folder to that
        /// target's modules.
        /// It obtains the modules from index store records for the target's Swift source files.
        private func catalogModules(targets: Set<XcodeTarget>, sourceFiles: Set<SourceFile>) -> [FilePath: Set<String>] {
            let modulesBySourcePath = Dictionary(
                sourceFiles.map { ($0.path.lexicallyNormalized(), $0.modules) },
                uniquingKeysWith: { $0.union($1) }
            )
            var modulesByCatalog: [FilePath: Set<String>] = [:]

            for target in targets {
                let targetModules = target.swiftSourceFiles.reduce(into: Set<String>()) { result, path in
                    result.formUnion(modulesBySourcePath[path] ?? [])
                }

                for catalog in target.files(kind: .xcStrings) {
                    modulesByCatalog[catalog, default: []].formUnion(targetModules)
                }
            }

            return modulesByCatalog
        }
    }
#endif
