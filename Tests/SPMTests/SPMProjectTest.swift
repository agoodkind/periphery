@testable import TestShared
import XCTest

final class SPMProjectTest: SPMSourceGraphTestCase {
    override static func setUp() {
        super.setUp()

        let configuration = nativeBuildConfiguration()
        build(projectPath: SPMProjectPath, configuration: configuration)
        index(configuration: configuration)
    }

    func testMainEntryFile() {
        assertReferenced(.functionFree("main()"))
    }

    func testCrossModuleReference() {
        assertReferenced(.class("PublicCrossModuleReferenced"))
        assertNotReferenced(.class("PublicCrossModuleNotReferenced"))
    }

    func testMacroImport() {
        assertReferenced(.module("SPMProjectKit"))
    }

    func testLocalizedStrings() {
        assertReferenced(.localizedString("spm_used_key"))
        assertNotReferenced(.localizedString("spm_unused_key"))
    }
}
