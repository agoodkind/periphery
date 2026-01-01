import Configuration
@testable import TestShared

final class SwiftUIProjectTest: XcodeSourceGraphTestCase {
    override static func setUp() {
        super.setUp()

        let configuration = Configuration()
        configuration.schemes = ["SwiftUIProject"]

        build(projectPath: SwiftUIProjectPath, configuration: configuration)
        index(configuration: configuration)
    }

    func testRetainsMainAppEntryPoint() {
        assertReferenced(.struct("SwiftUIProjectApp"))
    }

    func testDoesNotRetainPreviewProvider() {
        assertNotReferenced(.struct("PreviewOnlyView"))
        assertNotReferenced(.struct("PreviewOnlyView_PreviewProvider"))
    }

    func testRetainsPreviewOnlyCodeReferencedFromLivePreview() {
        assertReferenced(.enum("LivePreviewSampleData")) {
            self.assertReferenced(.varStatic("title"))
        }
    }

    func testDoesNotRetainCodeReferencedOnlyFromDeadPreview() {
        assertNotReferenced(.struct("DeadPreviewedView"))
        assertNotReferenced(.enum("DeadPreviewSampleData"))
    }

    func testRetainsLibraryContentProvider() {
        assertReferenced(.struct("LibraryOnlyView"))
        assertReferenced(.struct("LibraryOnlyView_LibraryContentProvider"))
    }

    func testRetainsUIApplicationDelegateAdaptorProperty() {
        assertReferenced(.struct("SwiftUIProjectApp")) {
            self.assertReferenced(.varInstance("appDelegate"))
        }
    }

    func testRetainsUIApplicationDelegateAdaptorReferencedType() {
        assertReferenced(.class("AppDelegate"))
    }

    func testLocalizedStrings() {
        assertReferenced(.localizedString("swiftui_used_key"))
        assertReferenced(.localizedString("swiftui_text_key"))
        assertNotReferenced(.localizedString("swiftui_unused_key"))
    }
}
