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
            let notesPrefix = "Release notes: "
            let releaseNotes = try XCTUnwrap(lines.first { $0.hasPrefix(notesPrefix) }, output)
            let releaseURL = try XCTUnwrap(URL(string: String(releaseNotes.dropFirst(notesPrefix.count))), output)
            let components = try XCTUnwrap(URLComponents(url: releaseURL, resolvingAgainstBaseURL: false), output)
            let tagPrefix = "/agoodkind/periphery/releases/tag/"
            guard components.scheme == "https", components.host == "github.com", components.port == nil,
                  components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
                  components.percentEncodedPath.hasPrefix(tagPrefix),
                  let latestVersion = String(components.percentEncodedPath.dropFirst(tagPrefix.count)).removingPercentEncoding,
                  !latestVersion.isEmpty
            else {
                XCTFail("The release notes URL must identify a fork release: \(releaseURL)")
                return
            }

            var request = URLRequest(url: releaseURL)
            request.httpMethod = "HEAD"
            let (_, response) = try await URLSession.shared.data(for: request)
            let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
            XCTAssertEqual(httpResponse.statusCode, 200)
            XCTAssertEqual(httpResponse.url, releaseURL, output)

            if installedVersion == "development" {
                XCTAssertTrue(lines.contains("This development build does not have a release version. The latest fork release is \(latestVersion)."), output)
            } else if latestVersion == installedVersion {
                XCTAssertTrue(lines.contains("The installed version matches the latest fork release, \(installedVersion)."), output)
            } else {
                let messages = [
                    "Version \(latestVersion) is available. The installed version is \(installedVersion).",
                    "The installed version is \(installedVersion). The latest fork release is \(latestVersion).",
                ]
                XCTAssertTrue(lines.contains { messages.contains(String($0)) }, output)
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
