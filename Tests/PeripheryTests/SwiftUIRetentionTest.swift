#if os(macOS)
    @testable import TestShared
    import XCTest

    final class SwiftUIRetentionTest: FixtureSourceGraphTestCase {
        func testRetainsMacroStatePropertyReferencedOnlyViaProjectedValue() {
            analyze(retainPublic: true) {
                assertReferenced(.struct("FixtureStruct228")) {
                    self.assertReferenced(.varInstance("onlyProjected"))
                    self.assertNotReferenced(.varInstance("unusedState"))
                }
            }
        }

        func testRetainsMacroStatePropertyReferencedOnlyViaBackingStorage() {
            analyze(retainPublic: true) {
                assertReferenced(.struct("FixtureStruct229")) {
                    self.assertReferenced(.varInstance("onlyBacking"))
                    self.assertNotReferenced(.varInstance("unusedState"))
                }
            }
        }

        func testRetainsPropertyWrapperPropertiesReferencedOnlyViaProjectedValue() {
            analyze(retainPublic: true) {
                assertReferenced(.struct("FixtureStruct230")) {
                    self.assertReferenced(.varInstance("dismiss"))
                    self.assertReferenced(.varInstance("focused"))
                    self.assertReferenced(.varInstance("stored"))
                    self.assertReferenced(.varInstance("scene"))
                    self.assertReferenced(.varInstance("model"))
                    self.assertReferenced(.varInstance("binding"))
                    self.assertNotReferenced(.varInstance("unusedEnvironment"))
                    self.assertNotReferenced(.varInstance("unusedFocus"))
                    self.assertNotReferenced(.varInstance("unusedStored"))
                }
            }
        }

        /// The test checks that Periphery reports `FixtureStruct231.assignedViaBacking` as unused when `init` only
        /// assigns `_assignedViaBacking` and the fixture never reads the property.
        /// `SwiftUIRetainer` adds a reference to the `@State` property only for explicit reads of `$name` or `_name`.
        /// The assignment `_assignedViaBacking = State(wrappedValue: flag)` counts as a write.
        func testReportsMacroStatePropertyInitializedOnlyViaBackingStorage() {
            analyze(retainPublic: true) {
                assertReferenced(.struct("FixtureStruct231")) {
                    self.assertNotReferenced(.varInstance("assignedViaBacking"))
                }
            }
        }
    }
#endif
