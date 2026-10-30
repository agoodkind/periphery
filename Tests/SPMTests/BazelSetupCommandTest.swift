#if os(macOS)
    import Foundation
    import XCTest

    final class BazelSetupCommandTest: XCTestCase {
        func testRejectsInvalidGitTags() throws {
            let testBundle = try XCTUnwrap(Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") })
            let executableURL = testBundle.bundleURL.deletingLastPathComponent().appendingPathComponent("periphery")
            let versionProcess = Process()
            versionProcess.executableURL = executableURL
            versionProcess.arguments = ["version"]
            let versionOutput = Pipe()
            versionProcess.standardOutput = versionOutput
            try versionProcess.run()
            let versionData = try XCTUnwrap(versionOutput.fileHandleForReading.readToEnd())
            versionProcess.waitUntilExit()
            XCTAssertEqual(versionProcess.terminationStatus, 0)
            let version = try XCTUnwrap(String(data: versionData, encoding: .utf8))
            try XCTSkipUnless(version.trimmingCharacters(in: .whitespacesAndNewlines) == "development", "Release builds do not prompt for a tag.")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try "module(name = \"consumer\")\n".write(to: directory.appendingPathComponent("MODULE.bazel"), atomically: true, encoding: .utf8)

            for tag in ["bad\ttag", "bad\\tag", "bad\0tag"] {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = ["scan", "--setup", "--disable-update-check"]
                process.currentDirectoryURL = directory
                let input = Pipe()
                let output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = output
                try process.run()
                input.fileHandleForWriting.write(Data("\(tag)\n".utf8))
                try input.fileHandleForWriting.close()
                let outputData = try XCTUnwrap(output.fileHandleForReading.readToEnd())
                process.waitUntilExit()
                let text = try XCTUnwrap(String(data: outputData, encoding: .utf8))
                XCTAssertNotEqual(process.terminationStatus, 0, text)
                XCTAssertTrue(text.contains("Invalid fork release tag"), text)
            }
        }
    }
#endif
