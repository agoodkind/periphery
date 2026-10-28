#if os(macOS)
    @testable import TestShared
    import XCTest

    final class SPMProjectMacOSTest: SPMSourceGraphTestCase {
        override static func setUp() {
            super.setUp()

            let configuration = nativeBuildConfiguration()

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

        func testStatePropertyReads() {
            assertReferenced(.struct("StateMacroView")) {
                self.assertReferenced(.varInstance("projected"))
                self.assertReferenced(.varInstance("direct"))
                self.assertReferenced(.varInstance("backing"))
                self.assertReferenced(.varInstance("qualified"))
                self.assertReferenced(.varInstance("crossFile"))
                self.assertReferenced(.varInstance("rootRead"))
                self.assertNotReferenced(.varInstance("unused"))
                self.assertNotReferenced(.varInstance("deadBinding"))
                self.assertNotReferenced(.functionMethodInstance("unusedBinding()"))
            }
        }
    }
#endif
