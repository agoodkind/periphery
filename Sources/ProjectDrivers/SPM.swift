import Configuration
import Extensions
import Foundation
import Logger
import Shared
import SystemPackage

public enum SPM {
    public static var isSupported: Bool {
        FilePath.current.appending("Package.swift").exists
    }

    public struct Package {
        public let path: FilePath = .current

        private let configuration: Configuration
        private let shell: Shell
        private let logger: Logger

        public init(configuration: Configuration, shell: Shell, logger: Logger) {
            self.configuration = configuration
            self.shell = shell
            self.logger = logger
        }

        public func clean() throws {
            try shell.exec(["swift", "package", "clean"])
        }

        public func build(additionalArguments: [String]) throws {
            try shell.exec(["swift", "build", "--build-tests"] + additionalArguments)
        }

        /// Build arguments that influence where SwiftPM places its products, and therefore the index store.
        /// Everything else (e.g. `--build-tests`, `-v`, `--skip-build`) has no effect on the location and is dropped.
        /// All of these options take a value, either as `--flag=value` or as a separate argument.
        static let locationOptions: Set<String> = [
            "-c", "--configuration",
            "--scratch-path", "--build-path",
            "--build-system",
            "--triple", "--arch", "--sdk", "--toolchain",
            "-Xswiftc",
        ]

        static func locationArguments(from buildArguments: [String]) -> [String] {
            var result: [String] = []
            var index = buildArguments.startIndex

            while index < buildArguments.endIndex {
                let argument = buildArguments[index]
                index = buildArguments.index(after: index)

                if let separator = argument.firstIndex(of: "="), locationOptions.contains(String(argument[..<separator])) {
                    result.append(argument)
                } else if locationOptions.contains(argument), index < buildArguments.endIndex {
                    result.append(argument)
                    result.append(buildArguments[index])
                    index = buildArguments.index(after: index)
                }
            }

            return result
        }

        /// The directory SwiftPM places build products in, as reported by `swift build --show-bin-path`.
        public func binPath(additionalArguments: [String]) throws -> FilePath {
            let arguments = ["swift", "build", "--show-bin-path"] + Self.locationArguments(from: additionalArguments)
            let output = try shell.exec(arguments)

            guard let line = output.split(whereSeparator: \.isNewline).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                throw PeripheryError.packageError(message: "Failed to determine the SwiftPM bin path: '\(arguments.joined(separator: " "))' produced no output.")
            }

            return FilePath(line.trimmingCharacters(in: .whitespaces))
        }

        /// Locates the index store of the package build described by `additionalArguments`.
        ///
        /// - Native backend: `<scratch>/<triple>/<configuration>/index/store`, i.e. `<binPath>/index/store`.
        /// - `swiftbuild` backend (default since Swift 6.4): `<scratch>/out/v5`, where `<binPath>` is
        ///   `<scratch>/out/Products/<Configuration>`, i.e. `<binPath>/../..`.
        public func indexStorePath(additionalArguments: [String]) throws -> FilePath {
            let binPath = try binPath(additionalArguments: additionalArguments)
            let candidates = [
                binPath.appending("index/store"),
                binPath.appending("../.."),
            ].map { $0.lexicallyNormalized() }

            if let store = candidates.first(where: { $0.appending("v5").exists }) {
                logger.contextualized(with: "spm:package").debug("Using index store at \(store)")
                return store
            }

            throw PeripheryError.spmIndexStoreNotFound(tried: candidates.map(\.string))
        }

        public func load() throws -> PackageDescription {
            logger.contextualized(with: "spm:package").debug("Loading \(FilePath.current)")

            let jsonData: Data

            if let path = configuration.jsonPackageManifestPath {
                jsonData = try Data(contentsOf: path.url)
            } else {
                let jsonString = try shell.exec(["swift", "package", "describe", "--type", "json"])

                guard let data = jsonString.data(using: .utf8) else {
                    throw PeripheryError.packageError(message: "Failed to read swift package description.")
                }

                jsonData = data
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(PackageDescription.self, from: jsonData)
        }
    }
}

public struct PackageDescription: Decodable {
    public let targets: [Target]
}

public struct Target: Decodable {
    public let name: String
    public let type: String
    public let path: String
    public let resources: [Resource]?

    public var isTestTarget: Bool {
        type == "test"
    }
}

public struct Resource: Decodable {
    public let path: String
}
