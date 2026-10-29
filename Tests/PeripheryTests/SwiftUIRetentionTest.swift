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
        func testReportsMacroStatePropertyInitializedOnlyViaBackingStorage() throws {
            try skipUnlessStateIsMacro()

            analyze(retainPublic: true) {
                assertReferenced(.struct("FixtureStruct231")) {
                    self.assertNotReferenced(.varInstance("assignedViaBacking"))
                }
            }
        }

        // MARK: - Private

        /// This helper runs `xcodebuild -version` and reads the major Xcode version.
        /// It skips the test when that version is below 27.
        /// The Xcode 27 SDK declares SwiftUI `State` as an attached macro.
        /// Earlier SDKs declare `State` as a property wrapper.
        /// With those SDKs, the index store records an assignment to `_name` as a reference to `name`.
        private func skipUnlessStateIsMacro() throws {
            let versionOutput = try Self.shell.exec(["xcodebuild", "-version"])
            let majorVersion = versionOutput
                .split(whereSeparator: \.isWhitespace)
                .dropFirst()
                .first
                .flatMap { Int($0.split(separator: ".").first ?? "") } ?? 0

            try XCTSkipUnless(majorVersion >= 27, "This test requires the Xcode 27 SDK, which declares SwiftUI State as a macro.")
        }
    }
#endif
