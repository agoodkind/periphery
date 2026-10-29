import Logger
import Shared
import SystemPackage
@testable import TestShared
@testable import XcodeSupport
import XCTest

final class SyncedGroupProjectTest: XCTestCase {
    private var project: XcodeProject!

    override func setUp() {
        super.setUp()
        let logger = Logger(quiet: true, verbose: false, colorMode: .never)
        let shell = ShellImpl(logger: logger)
        let xcodebuild = Xcodebuild(shell: shell, logger: logger)
        var loadedProjectPaths: Set<FilePath> = []
        project = try! XcodeProject(
            path: SyncedGroupProjectPath,
            loadedProjectPaths: &loadedProjectPaths,
            xcodebuild: xcodebuild,
            shell: shell,
            logger: logger
        )
    }

    override func tearDown() {
        project = nil
        super.tearDown()
    }

    func testCollectsSynchronizedGroupFiles() throws {
        XCTAssertEqual(
            try interfaceBuilderFiles(of: "App"),
            [
                "Synced/Included.xib",
                "Synced/Nested/NestedIncluded.storyboard",
                "Synced/Referenced.xib",
            ]
        )
    }

    func testOmitsFilesExcludedByMembershipExceptions() throws {
        let files = try interfaceBuilderFiles(of: "App")

        XCTAssertFalse(files.contains("Synced/Excluded.xib"))
        XCTAssertFalse(files.contains("Synced/Nested/NestedExcluded.xib"))
    }

    func testMembershipExceptionsApplyPerTarget() throws {
        XCTAssertEqual(
            try interfaceBuilderFiles(of: "Widget"),
            [
                "Synced/Excluded.xib",
                "Synced/Nested/NestedExcluded.xib",
                "Synced/Nested/NestedIncluded.storyboard",
                "Synced/Referenced.xib",
                "WidgetOnly/Widget.xib",
            ]
        )
    }

    func testOmitsGroupsOfOtherTargets() throws {
        XCTAssertFalse(try interfaceBuilderFiles(of: "App").contains("WidgetOnly/Widget.xib"))
    }

    func testDoesNotDuplicateFilesReferencedByBothGroupAndBuildPhase() throws {
        let target = try identifiedTarget("App")
        let relativePaths = target.files(kind: .interfaceBuilder).map { $0.relativeTo(SyncedGroupProjectRoot).string }

        XCTAssertEqual(relativePaths.count(where: { $0.hasSuffix("Referenced.xib") }), 1)
        XCTAssertEqual(relativePaths.count(where: { $0.hasSuffix("Included.xib") }), 1)
    }

    func testDoesNotTreatSynchronizedGroupPlistsAsInfoPlists() throws {
        let target = try identifiedTarget("Widget")

        XCTAssertEqual(
            target.files(kind: .infoPlist).map { $0.relativeTo(SyncedGroupProjectRoot).string },
            ["Synced/Info.plist"]
        )
    }

    // MARK: - Private

    private func identifiedTarget(_ name: String) throws -> XcodeTarget {
        let target = try XCTUnwrap(project.targets.first { $0.name == name })
        try target.identifyFiles()
        return target
    }

    private func interfaceBuilderFiles(of name: String) throws -> Set<String> {
        try Set(identifiedTarget(name).files(kind: .interfaceBuilder).map {
            $0.relativeTo(SyncedGroupProjectRoot).string
        })
    }
}
