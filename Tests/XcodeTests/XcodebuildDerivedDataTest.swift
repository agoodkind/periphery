import Configuration
import Foundation
import Logger
import ProjectDrivers
import Shared
import SystemPackage
@testable import TestShared
@testable import XcodeSupport
import XCTest

final class XcodebuildDerivedDataTest: XCTestCase {
    private static let markerName = "periphery-clean-build-marker"

    private var logger: Logger!
    private var shell: Shell!
    private var xcodebuild: Xcodebuild!
    private var project: XcodeProject!

    override func setUpWithError() throws {
        try super.setUpWithError()

        logger = Logger(quiet: true, verbose: false, colorMode: .never)
        shell = ShellImpl(logger: logger)
        xcodebuild = Xcodebuild(shell: shell, logger: logger)
        var loadedProjectPaths: Set<FilePath> = []
        project = try XcodeProject(
            path: UIKitProjectPath,
            loadedProjectPaths: &loadedProjectPaths,
            xcodebuild: xcodebuild,
            shell: shell,
            logger: logger
        )
    }

    func testDerivedDataPathIsIndependentOfSchemeOrder() throws {
        let forward = try xcodebuild.derivedDataPath(for: project, schemes: ["UIKitProject", "NotificationServiceExtension", "LocalPackageTarget"])
        let reversed = try xcodebuild.derivedDataPath(for: project, schemes: ["LocalPackageTarget", "NotificationServiceExtension", "UIKitProject"])

        XCTAssertEqual(forward, reversed)
    }

    func testSchemesListWritesToPeripheryDerivedData() throws {
        let listPath = try xcodebuild.derivedDataPath(for: project, schemes: [])
        try removeItemIfPresent(at: listPath)

        let schemes = try project.schemes(additionalArguments: [])

        XCTAssertTrue(schemes.contains("UIKitProject"), "\(schemes)")
        XCTAssertFalse(try contentsOfDirectory(at: listPath).isEmpty, "\(listPath) is empty after xcodebuild -list")
    }

    func testCleanBuildRemovesListDerivedDataBeforeListingSchemes() throws {
        let listPath = try xcodebuild.derivedDataPath(for: project, schemes: [])
        try FileManager.default.createDirectory(atPath: listPath.string, withIntermediateDirectories: true)
        let markerPath = listPath.appending(Self.markerName)
        XCTAssertTrue(FileManager.default.createFile(atPath: markerPath.string, contents: Data()))

        let configuration = Configuration()
        configuration.schemes = ["UIKitProject"]
        configuration.cleanBuild = true
        _ = try XcodeProjectDriver(projectPath: UIKitProjectPath, configuration: configuration, shell: shell, logger: logger)

        XCTAssertFalse(markerPath.exists, "\(markerPath) survived --clean-build")
        XCTAssertFalse(try contentsOfDirectory(at: listPath).isEmpty, "\(listPath) is empty after xcodebuild -list")
    }

    // MARK: - Private

    private func removeItemIfPresent(at path: FilePath) throws {
        if path.exists {
            try FileManager.default.removeItem(atPath: path.string)
        }
    }

    private func contentsOfDirectory(at path: FilePath) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path.string)
    }
}
