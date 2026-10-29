import Configuration
import FilenameMatcher
import Logger
import Shared
import SourceGraph
import SystemPackage

final class XCStringsIndexer: Indexer {
    private let modulesByFile: [FilePath: Set<String>]
    private let graph: SourceGraphMutex
    private let logger: ContextualLogger
    private let configuration: Configuration

    required init(modulesByFile: [FilePath: Set<String>], graph: SourceGraphMutex, logger: ContextualLogger, configuration: Configuration) {
        self.modulesByFile = modulesByFile
        self.graph = graph
        self.logger = logger.contextualized(with: "xcstrings")
        self.configuration = configuration
        super.init(configuration: configuration)
    }

    func perform() throws {
        let (indexedFiles, excludedFiles) = filterIndexExcluded(from: Set(modulesByFile.keys))
        excludedFiles.forEach { self.logger.debug("Excluding \($0.string)") }

        let catalogMatchers = configuration.localizedStringCatalogExcludeMatchers
        let includedFiles = indexedFiles.filter { path in
            guard catalogMatchers.anyMatch(filename: path.string) else { return true }

            self.logger.debug("Excluding catalog \(path.string)")
            return false
        }

        try JobPool(jobs: Array(includedFiles)).forEach { [weak self] path in
            guard let self else { return }

            let modules = modulesByFile[path, default: []]

            if modules.isEmpty {
                logger.debug("Periphery retains all keys because it could not determine target membership for \(path.string)")
            }

            let elapsed = try Benchmark.measure {
                do {
                    let keys = try XCStringsParser(path: path).parse()
                    let sourceFile = SourceFile(path: path, modules: modules)

                    let location = Location(file: sourceFile, line: 1, column: 1)
                    let declarations = keys.map { key in
                        Declaration(
                            name: key,
                            kind: .localizedString,
                            usrs: ["xcstrings:\(path.string):\(key)"],
                            location: location
                        )
                    }

                    self.graph.withLock { $0.add(Set(declarations)) }
                } catch {
                    throw PeripheryError.localizedStringCatalogReadFailed(path: path, error: error)
                }
            }

            logger.debug("\(path.string) (\(elapsed)s)")
        }
    }
}
