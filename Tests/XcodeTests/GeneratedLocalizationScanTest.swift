import Foundation
@testable import TestShared
import XCTest

final class GeneratedLocalizationScanTest: XCTestCase {
    func testRetainsUsedGeneratedSymbol() throws {
        #if compiler(>=6.2)
            let fileManager = FileManager.default
            let temporaryURL = fileManager.temporaryDirectory
                .appendingPathComponent("periphery-generated-localization-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            let fixtureURL = URL(fileURLWithPath: SwiftUIProjectPath.string).deletingLastPathComponent()
            try fileManager.copyItem(at: fixtureURL, to: temporaryURL)
            defer { try? fileManager.removeItem(at: temporaryURL) }

            let sourceURL = temporaryURL.appendingPathComponent("SwiftUIProject/ContentView.swift")
            let source = """
            import SwiftUI

            struct ContentView: View {
                var body: some View {
                    if #available(iOS 16, *) {
                        let resource: LocalizedStringResource = .generatedUsed
                        VStack {
                            Text(String(localized: resource))
                            Text(String(localized: .numberOfItems(3)))
                            Text(.now, style: .date)
                        }
                    }
                }
            }
            """
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)

            let catalogURL = temporaryURL.appendingPathComponent("SwiftUIProject/Localizable.xcstrings")
            let catalog = #"{"sourceLanguage":"en","strings":{"generated.used":{"extractionState":"manual","localizations":{"en":{"stringUnit":{"state":"translated","value":"Used"}}}},"generated.unused":{"extractionState":"manual","localizations":{"en":{"stringUnit":{"state":"translated","value":"Unused"}}}},"number.of.items %lld":{"extractionState":"manual","localizations":{"en":{"stringUnit":{"state":"translated","value":"%lld items"}}}}},"version":"1.0"}"#
            try catalog.write(to: catalogURL, atomically: true, encoding: .utf8)

            let derivedDataURL = temporaryURL.appendingPathComponent("DerivedData")
            let build = try run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: [
                    "xcodebuild", "-project", temporaryURL.appendingPathComponent("SwiftUIProject.xcodeproj").path,
                    "-scheme", "SwiftUIProject", "-destination", "generic/platform=iOS", "-quiet",
                    "-derivedDataPath", derivedDataURL.path, "build-for-testing", "CODE_SIGNING_ALLOWED=NO",
                    "STRING_CATALOG_GENERATE_SYMBOLS=YES", "COMPILER_INDEX_STORE_ENABLE=YES", "INDEX_ENABLE_DATA_STORE=YES",
                ]
            )
            XCTAssertEqual(build.status, 0, build.output)
            guard build.status == 0 else { return }

            let testBundle = try XCTUnwrap(Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") })
            let executableURL = testBundle.bundleURL.deletingLastPathComponent().appendingPathComponent("periphery")
            let scanArguments = [
                "scan", "--disable-update-check", "--project-root", temporaryURL.path,
                "--project", "SwiftUIProject.xcodeproj", "--schemes", "SwiftUIProject", "--skip-build",
                "--index-store-path", derivedDataURL.appendingPathComponent("Index.noindex/DataStore").path,
            ]
            let scan = try run(executable: executableURL, arguments: scanArguments)
            XCTAssertEqual(scan.status, 0, scan.output)
            XCTAssertFalse(scan.output.contains("Unused localized string 'generated.used'"), scan.output)
            XCTAssertFalse(scan.output.contains("Unused localized string 'number.of.items %lld'"), scan.output)
            XCTAssertTrue(scan.output.contains("Unused localized string 'generated.unused'"), scan.output)
            XCTAssertTrue(scan.output.contains("DeadPreviewedView"), scan.output)

            let generatedURL = derivedDataURL.appendingPathComponent(
                "Build/Intermediates.noindex/SwiftUIProject.build/Debug-iphoneos/SwiftUIProject.build/DerivedSources/GeneratedStringSymbols_Localizable.swift"
            )
            try fileManager.removeItem(at: generatedURL)
            let fallback = try run(executable: executableURL, arguments: scanArguments)
            XCTAssertEqual(fallback.status, 0, fallback.output)
            XCTAssertFalse(fallback.output.contains("Unused localized string 'generated.used'"), fallback.output)
            XCTAssertFalse(fallback.output.contains("Unused localized string 'number.of.items %lld'"), fallback.output)
            XCTAssertFalse(fallback.output.contains("Unused localized string 'generated.unused'"), fallback.output)
        #else
            throw XCTSkip("Generated String Catalog symbols require Xcode 26 or newer")
        #endif
    }

    private func run(executable: URL, arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        let data = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        return try (process.terminationStatus, XCTUnwrap(String(data: data, encoding: .utf8)))
    }
}
