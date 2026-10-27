#if os(macOS)
    import Configuration
    @testable import TestShared
    import XCTest

    final class SPMProjectMacOSTest: SPMSourceGraphTestCase {
        override static func setUp() {
            super.setUp()

            let configuration = Configuration()
            configuration.buildArguments = ["--build-system", "native"]
            build(projectPath: SPMProjectMacOSPath, configuration: configuration)
            index(configuration: configuration)
        }

        func testRetainsInterfaceBuilderDeclarations() {
            assertReferenced(.class("SPMXibViewController")) {
                // Referenced via XIB (connected)
                self.assertReferenced(.functionMethodInstance("buttonTapped(_:)"))
                self.assertReferenced(.varInstance("button"))
                self.assertReferenced(.varInstance("borderWidth"))
                // Unreferenced - not connected in XIB
                self.assertNotReferenced(.varInstance("unusedMacOutlet"))
                self.assertNotReferenced(.functionMethodInstance("unusedMacAction(_:)"))
                self.assertNotReferenced(.varInstance("unusedMacInspectable"))
            }
        }
    }
#endif
