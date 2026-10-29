#if os(macOS)
    import Configuration
    @testable import TestShared
    import XCTest

    final class SPMProjectMacOSLocalizedStringTest: SPMSourceGraphTestCase {
        override static func setUp() {
            super.setUp()

            let configuration = nativeBuildConfiguration()
            configuration.buildFilenameMatchers()
            build(projectPath: SPMProjectMacOSPath, configuration: configuration)
            index(configuration: configuration)
        }

        func testRetainsKeysPassedToLocalizedParameters() {
            assertReferenced(.localizedString("mac_button_key"))
            assertReferenced(.localizedString("mac_label_key"))
            assertReferenced(.localizedString("mac_toggle_key"))
            assertReferenced(.localizedString("mac_section_key"))
            assertReferenced(.localizedString("mac_navigation_title_key"))
            assertReferenced(.localizedString("mac_text_key"))
            assertReferenced(.localizedString("mac_ternary_true_key"))
            assertReferenced(.localizedString("mac_ternary_false_key"))
            assertReferenced(.localizedString("mac_custom_init_key"))
            assertReferenced(.localizedString("mac_resource_param_key"))
            assertReferenced(.localizedString("mac_localization_value_param_key"))
            assertReferenced(.localizedString("mac_variadic_key"))
        }

        func testRetainsKeysFromLocalizedDeclarationTypes() {
            assertReferenced(.localizedString("mac_annotated_property_key"))
            assertReferenced(.localizedString("mac_returned_resource_key"))
            assertReferenced(.localizedString("mac_default_value_key"))
        }

        func testDoesNotRetainKeysPassedToStringParameters() {
            assertNotReferenced(.localizedString("mac_plain_string_param_key"))
            assertNotReferenced(.localizedString("mac_label_system_image_key"))
            assertNotReferenced(.localizedString("mac_unused_key"))
        }

        func testExcludesInfoPlistAndAppShortcutsCatalogsByDefault() {
            assertNotIndexed(.localizedString("NSCameraUsageDescription"))
            assertNotIndexed(.localizedString("mac_shortcut_phrase"))
        }
    }

    final class SPMProjectMacOSLocalizedStringCatalogExcludeTest: SPMSourceGraphTestCase {
        override static func setUp() {
            super.setUp()

            let configuration = nativeBuildConfiguration()
            configuration.localizedStringCatalogExclude = ["**/Localizable.xcstrings"]
            configuration.buildFilenameMatchers()
            build(projectPath: SPMProjectMacOSPath, configuration: configuration)
            index(configuration: configuration)
        }

        func testExcludesConfiguredCatalogs() {
            assertNotIndexed(.localizedString("mac_unused_key"))
            assertNotIndexed(.localizedString("mac_button_key"))
            assertNotReferenced(.localizedString("NSCameraUsageDescription"))
            assertNotReferenced(.localizedString("mac_shortcut_phrase"))
        }
    }
#endif
