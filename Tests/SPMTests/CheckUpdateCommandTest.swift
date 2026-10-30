#if os(macOS)
    import Foundation
    import XCTest

    final class CheckUpdateCommandTest: XCTestCase {
        func testReportsLatestForkRelease() async throws {
            let testBundle = try XCTUnwrap(Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") })
            let executableURL = testBundle.bundleURL.deletingLastPathComponent().appendingPathComponent("periphery")
            let installedVersion = try run(executableURL, arguments: ["version"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let output = try run(executableURL, arguments: ["check-update"])
            let lines = output.split(separator: "\n")
            let releaseNotes = try XCTUnwrap(lines.first { $0.hasPrefix("Release notes: ") }, output)

            var request = try URLRequest(url: XCTUnwrap(URL(string: "https://github.com/agoodkind/periphery/releases/latest")))
            request.httpMethod = "HEAD"
            let (_, response) = try await URLSession.shared.data(for: request)
            let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
            XCTAssertEqual(httpResponse.statusCode, 200)
            let finalURL = try XCTUnwrap(httpResponse.url)
            XCTAssertEqual(releaseNotes, "Release notes: \(finalURL.absoluteString)", output)

            if installedVersion == "development" {
                let messagePrefix = "This development build does not have a release version. The latest fork release is "
                let message = try XCTUnwrap(lines.first { $0.hasPrefix(messagePrefix) && $0.hasSuffix(".") }, output)
                let tag = String(message.dropFirst(messagePrefix.count).dropLast())
                let tagBase = try XCTUnwrap(URL(string: "https://github.com/agoodkind/periphery/releases/tag/"))
                XCTAssertEqual(tagBase.appendingPathComponent(tag).path, finalURL.path, output)
            } else if finalURL.absoluteString == "https://github.com/agoodkind/periphery/releases/tag/\(installedVersion)" {
                XCTAssertTrue(lines.contains("The installed version matches the latest fork release, \(installedVersion)."), output)
            } else {
                XCTAssertTrue(lines.contains { $0.contains(installedVersion) }, output)
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
