import Foundation
import Logger
import SystemPackage
@testable import XcodeSupport
import XCTest

final class XcodebuildDerivedDataPathTest: XCTestCase {
    func testDerivedDataPathIsIndependentOfSchemeOrder() throws {
        let shell = ShellMock(output: "Xcode 0.0")
        let logger = Logger(quiet: true, verbose: false, colorMode: .never)
        var loadedProjectPaths: Set<FilePath> = []
        let xcodebuild = Xcodebuild(shell: shell, logger: logger)
        let project = try XcodeProject(path: UIKitProjectPath, loadedProjectPaths: &loadedProjectPaths, xcodebuild: xcodebuild, shell: shell, logger: logger)

        let forward = try xcodebuild.derivedDataPath(for: project, schemes: ["SchemeA", "SchemeB", "SchemeC"])
        let reversed = try xcodebuild.derivedDataPath(for: project, schemes: ["SchemeC", "SchemeB", "SchemeA"])
        let shuffled = try xcodebuild.derivedDataPath(for: project, schemes: ["SchemeB", "SchemeC", "SchemeA"])

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward, shuffled)
    }
}
