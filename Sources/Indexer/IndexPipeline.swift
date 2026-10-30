import Configuration
import Foundation
import IndexStore
import Logger
import Shared
import SourceGraph
import SyntaxAnalysis

public struct IndexPipeline {
    private let plan: IndexPlan
    private let graph: SourceGraphMutex
    private let logger: ContextualLogger
    private let configuration: Configuration
    private let swiftVersion: SwiftVersion

    public init(plan: IndexPlan, graph: SourceGraphMutex, logger: ContextualLogger, configuration: Configuration, swiftVersion: SwiftVersion) {
        self.plan = plan
        self.graph = graph
        self.logger = logger
        self.configuration = configuration
        self.swiftVersion = swiftVersion
    }

    public func perform() throws -> Int {
        let generatedFiles = plan.sourceFiles.filter { file, _ in
            SourceFileCollector.isGeneratedStringSymbols(file.path)
        }
        let sourceFiles = plan.sourceFiles.filter { generatedFiles[$0.key] == nil }
        let generatedSymbols = try generatedSymbolsByUsr(generatedFiles)
        let generatedKeys = generatedSymbols.keys
        logger.debug("Read \(generatedKeys.count) generated localization symbols from \(generatedFiles.count) files")
        let scannedLOC = try SwiftIndexer(
            sourceFiles: sourceFiles,
            graph: graph,
            logger: logger,
            configuration: configuration,
            swiftVersion: swiftVersion,
            generatedStringSymbolUsrs: Set(generatedKeys.keys),
            generatedStringSymbolModules: generatedSymbols.modules
        ).perform()

        graph.withLock { graph in
            for (usr, keys) in generatedKeys where !graph.references(to: usr).isEmpty {
                graph.addUsedLocalizedStringKeys(keys)
            }
        }

        if !plan.plistPaths.isEmpty {
            try InfoPlistIndexer(
                infoPlistFiles: plan.plistPaths,
                graph: graph,
                logger: logger,
                configuration: configuration
            ).perform()
        }

        if !plan.xibPaths.isEmpty {
            try XibIndexer(
                xibFiles: plan.xibPaths,
                graph: graph,
                logger: logger,
                configuration: configuration
            ).perform()
        }

        if !plan.xcDataModelPaths.isEmpty {
            try XCDataModelIndexer(
                files: plan.xcDataModelPaths,
                graph: graph,
                logger: logger,
                configuration: configuration
            ).perform()
        }

        if !plan.xcMappingModelPaths.isEmpty {
            try XCMappingModelIndexer(
                files: plan.xcMappingModelPaths,
                graph: graph,
                logger: logger,
                configuration: configuration
            ).perform()
        }

        if !plan.xcStringsPaths.isEmpty, !configuration.disableUnusedLocalizedStringAnalysis {
            try XCStringsIndexer(
                modulesByFile: plan.xcStringsPaths,
                graph: graph,
                logger: logger,
                configuration: configuration
            ).perform()
        }

        graph.withLock { $0.indexingComplete() }
        return scannedLOC
    }

    private func generatedSymbolsByUsr(_ files: [SourceFile: [IndexUnit]]) throws -> (keys: [String: Set<String>], modules: [String: Set<String>]) {
        var keysByUsr: [String: Set<String>] = [:]
        var modulesByUsr: [String: Set<String>] = [:]
        for (file, units) in files {
            let keysByLine: [Int: String]
            if file.path.exists {
                let source = try String(contentsOfFile: file.path.string, encoding: .utf8)
                keysByLine = GeneratedStringSymbols.keys(in: source)
            } else {
                keysByLine = [:]
            }
            for unit in units {
                guard let recordName = unit.unit.recordName else { continue }

                let record = try RecordReader(indexStore: unit.store, recordName: recordName)
                record.forEach(occurrence: { occurrence in
                    guard occurrence.roles.contains(.definition),
                          [.staticProperty, .staticMethod].contains(occurrence.symbol.kind)
                    else { return }

                    let usr = occurrence.symbol.usr
                    if let key = keysByLine[occurrence.location.line] {
                        keysByUsr[usr, default: []].insert(key)
                    }
                    if !unit.unit.moduleName.isEmpty {
                        modulesByUsr[usr, default: []].insert(unit.unit.moduleName)
                    }
                })
            }
        }
        return (keysByUsr, modulesByUsr)
    }
}
