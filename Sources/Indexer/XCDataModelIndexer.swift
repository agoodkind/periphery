import Configuration
import Foundation
import Logger
import Shared
import SourceGraph
import SystemPackage

final class XCDataModelIndexer: Indexer {
    enum XCDataModelError: Error, CustomStringConvertible {
        case failedToParse(path: FilePath, underlyingError: Error)

        var description: String {
            switch self {
            case let .failedToParse(path, underlyingError):
                "Could not read or parse Core Data model at \(path.string): \(underlyingError.localizedDescription)"
            }
        }
    }

    private let files: Set<FilePath>
    private let graph: SourceGraphMutex
    private let logger: ContextualLogger

    required init(files: Set<FilePath>, graph: SourceGraphMutex, logger: ContextualLogger, configuration: Configuration) {
        self.files = files
        self.graph = graph
        self.logger = logger.contextualized(with: "xcdatamodel")
        super.init(configuration: configuration)
    }

    func perform() throws {
        let (includedFiles, excludedFiles) = filterIndexExcluded(from: files)
        excludedFiles.forEach { self.logger.debug("Excluding \($0.string)") }

        try JobPool(jobs: Array(includedFiles)).forEach { [weak self] path in
            guard let self else { return }

            let elapsed = try Benchmark.measure {
                do {
                    let input = try ModelInput(path: path, kind: .data)
                    let refs = try XCDataModelParser(input: input)
                        .parse()
                    self.graph.withLock { graph in
                        refs.forEach { graph.add($0) }
                    }
                } catch {
                    throw XCDataModelError.failedToParse(path: path, underlyingError: error)
                }
            }

            logger.debug("\(path.string) (\(elapsed)s)")
        }
    }
}
