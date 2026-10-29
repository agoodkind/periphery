import Configuration
@testable import TestShared
import XCTest

final class SPMProjectLocalizedStringOptOutTest: SPMSourceGraphTestCase {
    override static func setUp() {
        super.setUp()

        let configuration = nativeBuildConfiguration()
        configuration.disableUnusedLocalizedStringAnalysis = true
        build(projectPath: SPMProjectPath, configuration: configuration)
        index(configuration: configuration)
    }

    func testDisableUnusedLocalizedStringAnalysis() {
        assertNotIndexed(.localizedString("spm_used_key"))
        assertNotIndexed(.localizedString("spm_unused_key"))
    }
}
