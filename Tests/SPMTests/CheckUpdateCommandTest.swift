#if os(macOS)
    import Foundation
    import XCTest

    final class CheckUpdateCommandTest: XCTestCase {
        func testReportsLatestForkRelease() throws {
            let testBundle = try XCTUnwrap(Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") })
            let executableURL = testBundle.bundleURL.deletingLastPathComponent().appendingPathComponent("periphery")
            let installedVersion = try run(executableURL, arguments: ["version"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let output = try run(executableURL, arguments: ["check-update"])
            let lines = output.split(separator: "\n")
            let prefix = "Release notes: https://github.com/agoodkind/periphery/releases/tag/"
            let releaseNotes = try XCTUnwrap(lines.first { $0.hasPrefix(prefix) }, output)
            let latestVersion = String(releaseNotes.dropFirst(prefix.count))
            XCTAssertFalse(latestVersion.isEmpty, output)

            if installedVersion == "development" {
                XCTAssertTrue(lines.contains("This development build does not have a release version. The latest fork release is \(latestVersion)."), output)
            } else if installedVersion == latestVersion {
                XCTAssertTrue(lines.contains("The installed version matches the latest fork release, \(latestVersion)."), output)
            } else {
                XCTAssertTrue(lines.contains { $0.contains(installedVersion) && $0.contains(latestVersion) }, output)
            }
        }

        private func run(_ executableURL: URL, arguments: [String]) throws -> String {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            try process.run()
            let outputData = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()

            let output = try XCTUnwrap(String(bytes: outputData, encoding: .utf8))
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "CheckUpdateCommandTest", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Command \(arguments.joined(separator: " ")) exited with status \(process.terminationStatus): \(output)"])
            }

            return output
        }
    }
#endif
