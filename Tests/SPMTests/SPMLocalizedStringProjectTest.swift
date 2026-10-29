#if os(macOS)
    import Configuration
    import Foundation
    @testable import Indexer
    import ProjectDrivers
    import Shared
    @testable import SourceGraph
    import SystemPackage
    @testable import TestShared
    import XCTest

    final class SPMLocalizedStringProjectTest: SPMSourceGraphTestCase {
        override static func setUp() {
            super.setUp()

            let configuration = Configuration()
            build(projectPath: SPMLocalizedStringProjectPath, configuration: configuration)
            index(configuration: configuration)
        }

        func testRetainsInterpolatedKeysAndReportsUnrelatedKey() {
            assertReferenced(.localizedString("interpolation_count %lld items"))
            assertReferenced(.localizedString("interpolation_greeting %@"))
            assertReferenced(.localizedString("interpolation_ratio %lf"))
            assertNotReferenced(.localizedString("interpolation_unrelated_key"))
        }

        func testRetainsEveryKeyOfModuleWithUnresolvedKey() {
            assertReferenced(.localizedString("dynamic_plain_key"))
            assertReferenced(.localizedString("dynamic_runtime_key"))
            assertReferenced(.localizedString("dynamic_unreferenced_key"))
        }

        func testReportsUnusedPlainKey() {
            assertReferenced(.localizedString("plain_used_key"))
            assertNotReferenced(.localizedString("plain_unused_key"))
        }

        func testResolvesKeysFromReceivingParameterTypes() {
            assertReferenced(.localizedString("plain_text_with_comment_key"))
            assertNotReferenced(.localizedString("plain_comment_not_key"))
            assertReferenced(.localizedString("plain_function_type_title_key"))
            assertNotReferenced(.localizedString("plain_generic_not_key"))
            assertReferenced(.localizedString("plain_private_function_key"))
        }

        func testRetainsKeysPassedToUnresolvedCallees() {
            assertReferenced(.localizedString("plain_objc_callee_key"))
            assertReferenced(.localizedString("plain_closure_key"))
        }

        func testRetainsKeysMatchingUnresolvedPrefix() {
            assertReferenced(.localizedString("settings.display"))
            assertReferenced(.localizedString("settings.sound"))
            assertNotReferenced(.localizedString("prefix_unused_key"))
        }

        func testAssignsCatalogToTargetDeclaringItAsResource() {
            assertReferenced(.localizedString("owner_a_used_key"))
            assertNotReferenced(.localizedString("owner_a_unused_key"))
        }
    }

    final class SPMLocalizedStringUnownedCatalogTest: SPMSourceGraphTestCase {
        private static var temporaryDirectory: FilePath!

        override static func setUp() {
            super.setUp()

            let configuration = Configuration()
            build(projectPath: SPMLocalizedStringProjectPath, configuration: configuration)

            var indexStorePath: FilePath?
            SPMLocalizedStringProjectPath.chdir {
                let package = SPM.Package(configuration: configuration, shell: shell, logger: logger)
                indexStorePath = try! package.indexStorePath(additionalArguments: [])
            }

            temporaryDirectory = FilePath(
                FileManager.default.temporaryDirectory
                    .appendingPathComponent("periphery-unowned-catalog-\(UUID().uuidString)")
                    .resolvingSymlinksInPath()
                    .path
            )
            try! FileManager.default.createDirectory(atPath: temporaryDirectory.string, withIntermediateDirectories: true)

            let catalogPath = temporaryDirectory.appending("Unowned.xcstrings")
            let catalog = #"{ "sourceLanguage" : "en", "strings" : { "unowned_unreferenced_key" : {} } }"#
            try! catalog.write(toFile: catalogPath.string, atomically: true, encoding: .utf8)

            let configPath = temporaryDirectory.appending("generic.json")
            let genericConfig = """
            {
              "indexstores": ["\(indexStorePath!.string)"],
              "plists": [],
              "xibs": [],
              "xcdatamodels": [],
              "xcmappingmodels": [],
              "xcstrings": ["\(catalogPath.string)"],
              "test_targets": []
            }
            """
            try! genericConfig.write(toFile: configPath.string, atomically: true, encoding: .utf8)

            let driver = try! GenericProjectDriver(genericProjectConfig: configPath, configuration: configuration)
            plan = try! driver.plan(logger: logger.contextualized(with: "index"))
            index(configuration: configuration)
        }

        override static func tearDown() {
            try? FileManager.default.removeItem(atPath: temporaryDirectory.string)
            super.tearDown()
        }

        func testRetainsKeysOfCatalogWithoutTargetMembership() {
            assertReferenced(.localizedString("unowned_unreferenced_key"))
        }
    }

    final class SPMLocalizedStringCatalogReadFailureTest: SPMSourceGraphTestCase {
        private static let manifest = """
        // swift-tools-version:5.9
        import PackageDescription

        let package = Package(
            name: "CatalogReadFailure",
            targets: [.executableTarget(name: "CatalogReadFailure", exclude: ["Localizable.xcstrings"])]
        )

        """

        private var packagePath: FilePath!
        private var catalogPath: FilePath!

        override func setUpWithError() throws {
            try super.setUpWithError()

            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("periphery-catalog-failure-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            let sourcesURL = temporaryURL.appendingPathComponent("Sources/CatalogReadFailure")
            try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
            try Self.manifest.write(to: temporaryURL.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
            try "print(1)\n".write(to: sourcesURL.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
            packagePath = FilePath(temporaryURL.path)
            catalogPath = FilePath(sourcesURL.appendingPathComponent("Localizable.xcstrings").path)
        }

        override func tearDownWithError() throws {
            if catalogPath.exists {
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: catalogPath.string)
            }
            try FileManager.default.removeItem(atPath: packagePath.string)
            try super.tearDownWithError()
        }

        func testUnreadableCatalogFailsScan() throws {
            try #"{ "sourceLanguage" : "en", "strings" : {}, "version" : "1.0" }"#
                .write(toFile: catalogPath.string, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: catalogPath.string)

            assertScanFailsToReadCatalog()
        }

        func testMalformedCatalogFailsScan() throws {
            try "{ not json".write(toFile: catalogPath.string, atomically: true, encoding: .utf8)

            assertScanFailsToReadCatalog()
        }

        // MARK: - Private

        private func assertScanFailsToReadCatalog(file: StaticString = #filePath, line: UInt = #line) {
            let configuration = Configuration()
            Self.build(projectPath: packagePath, configuration: configuration)

            let graph = SourceGraph(configuration: configuration, logger: Self.logger)
            let pipeline = IndexPipeline(
                plan: Self.plan,
                graph: SourceGraphMutex(graph: graph),
                logger: Self.logger.contextualized(with: "index"),
                configuration: configuration,
                swiftVersion: Self.swiftVersion
            )

            XCTAssertThrowsError(try pipeline.perform(), file: file, line: line) { error in
                let description = error.localizedDescription
                let firstLine = description.split(separator: "\n").first.map(String.init) ?? ""
                XCTAssertTrue(firstLine.hasPrefix("Failed to read String Catalog at path: "), description, file: file, line: line)
                XCTAssertTrue(
                    firstLine.hasSuffix("/Sources/CatalogReadFailure/Localizable.xcstrings"),
                    description,
                    file: file,
                    line: line
                )
            }
        }
    }
#endif
