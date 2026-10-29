import Configuration
import Foundation
import ProjectDrivers
import Shared
import SystemPackage
@testable import TestShared
import XCTest

final class SPMIndexStoreLocationTest: SPMSourceGraphTestCase {
    private static let manifest = """
    // swift-tools-version:5.9
    import PackageDescription

    let package = Package(
        name: "IndexStoreLocation",
        targets: [.executableTarget(name: "IndexStoreLocation")]
    )

    """

    private static let mainSource = """
    print(usedFunction())

    """

    private static let functionsSource = """
    func usedFunction() -> Int {
        1
    }

    func plantedUnusedFunction() -> Int {
        2
    }

    """

    private var packagePath: FilePath!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("periphery-index-store-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        let sourcesURL = temporaryURL.appendingPathComponent("Sources/IndexStoreLocation")
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try Self.manifest.write(to: temporaryURL.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try Self.mainSource.write(to: sourcesURL.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try Self.functionsSource.write(to: sourcesURL.appendingPathComponent("Functions.swift"), atomically: true, encoding: .utf8)
        packagePath = FilePath(temporaryURL.path)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(atPath: packagePath.string)
        try super.tearDownWithError()
    }

    func testDefaultBuildSystemScanFindsIndexStore() {
        scan(buildArguments: [])

        assertReferenced(.functionFree("usedFunction()"))
        assertNotReferenced(.functionFree("plantedUnusedFunction()"))
    }

    func testNativeBuildSystemScanFindsIndexStore() {
        scan(buildArguments: ["--build-system", "native"])

        assertReferenced(.functionFree("usedFunction()"))
        assertNotReferenced(.functionFree("plantedUnusedFunction()"))
    }

    func testCustomScratchPathScanFindsIndexStoreUnderScratchPath() throws {
        let scratchPath = packagePath.appending("custom-scratch")
        let buildArguments = ["--scratch-path", scratchPath.string]
        scan(buildArguments: buildArguments)

        assertNotReferenced(.functionFree("plantedUnusedFunction()"))

        var storePath: FilePath?
        try packagePath.chdir {
            let package = SPM.Package(configuration: Configuration(), shell: Self.shell, logger: Self.logger)
            storePath = try package.indexStorePath(additionalArguments: buildArguments)
        }
        let resolvedStorePath = try XCTUnwrap(storePath)
        XCTAssertTrue(resolvedStorePath.starts(with: scratchPath), "\(resolvedStorePath) is not under \(scratchPath)")
    }

    func testScanWithoutIndexStoreFails() throws {
        let configuration = Configuration()
        configuration.skipBuild = true

        try packagePath.chdir {
            let driver = try SPMProjectDriver(configuration: configuration, shell: Self.shell, logger: Self.logger)
            try driver.build()

            XCTAssertThrowsError(try driver.plan(logger: Self.logger.contextualized(with: "index"))) { error in
                let description = error.localizedDescription
                XCTAssertTrue(description.hasPrefix("Failed to locate the SwiftPM index store."), description)
                XCTAssertTrue(description.contains("'--index-store-path'"), description)
            }
        }
    }

    // MARK: - Private

    private func scan(buildArguments: [String]) {
        let configuration = Configuration()
        configuration.buildArguments = buildArguments
        Self.build(projectPath: packagePath, configuration: configuration)
        index(configuration: configuration)
    }
}
