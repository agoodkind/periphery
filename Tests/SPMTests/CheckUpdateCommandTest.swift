#if os(macOS)
    import Foundation
    import XCTest

    final class CheckUpdateCommandTest: XCTestCase {
        func testDevelopmentBuildReportsLatestForkRelease() throws {
            let testBundle = try XCTUnwrap(Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") })
            let executableURL = testBundle.bundleURL.deletingLastPathComponent().appendingPathComponent("periphery")
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["check-update"]
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            try process.run()
            let outputData = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()

            let output = try XCTUnwrap(String(bytes: outputData, encoding: .utf8))
            XCTAssertEqual(process.terminationStatus, 0, output)
            let lines = output.split(separator: "\n")
            XCTAssertEqual(lines.count, 2, output)
            let firstLine = try XCTUnwrap(lines.first)
            let prefix = "This development build does not have a release version. The latest fork release is "
            XCTAssertTrue(firstLine.hasPrefix(prefix), output)
            XCTAssertTrue(firstLine.hasSuffix("."), output)
            guard firstLine.hasPrefix(prefix), firstLine.hasSuffix(".") else { return }

            let version = firstLine.dropFirst(prefix.count).dropLast()
            XCTAssertFalse(version.isEmpty, output)
            XCTAssertEqual(lines.last, "Release notes: https://github.com/agoodkind/periphery/releases/tag/\(version)")
        }
    }
#endif
