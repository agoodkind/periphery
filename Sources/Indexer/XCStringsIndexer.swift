import Configuration
import Logger
import Shared
import SourceGraph
import SystemPackage

final class XCStringsIndexer: Indexer {
    enum XCStringsError: Error {
        case failedToParse(path: FilePath, underlyingError: Error)
    }

    private let files: Set<FilePath>
    private let graph: SourceGraphMutex
    private let logger: ContextualLogger

    required init(files: Set<FilePath>, graph: SourceGraphMutex, logger: ContextualLogger, configuration: Configuration) {
        self.files = files
        self.graph = graph
        self.logger = logger.contextualized(with: "xcstrings")
        super.init(configuration: configuration)
    }

    func perform() throws {
        let (includedFiles, excludedFiles) = filterIndexExcluded(from: files)
        excludedFiles.forEach { self.logger.debug("Excluding \($0.string)") }

        try JobPool(jobs: Array(includedFiles)).forEach { [weak self] path in
            guard let self else { return }

            let elapsed = try Benchmark.measure {
                do {
                    let keys = try XCStringsParser(path: path).parse()
                    let sourceFile = SourceFile(path: path, modules: [])

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
                    throw XCStringsError.failedToParse(path: path, underlyingError: error)
                }
            }

            logger.debug("\(path.string) (\(elapsed)s)")
        }
    }
}
