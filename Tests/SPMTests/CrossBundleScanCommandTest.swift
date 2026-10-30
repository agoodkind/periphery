#if os(macOS)
    import Foundation
    import XCTest

    final class CrossBundleScanCommandTest: XCTestCase {
        func testCrossBundleAndModuleBundleLookups() throws {
            let project = try makeProject()
            defer { try? FileManager.default.removeItem(at: project) }

            let appOutput = try run(URL(fileURLWithPath: "/usr/bin/env"), ["swift", "run", "App"], in: project)
            XCTAssertTrue(appOutput.contains("Dynamic value"), appOutput)
            let lines = appOutput.split(separator: "\n")
            let mainBundle = try XCTUnwrap(lines.first { $0.hasPrefix("Main bundle: ") })
            let ownerBundle = try XCTUnwrap(lines.first { $0.hasPrefix("Owner bundle: ") })
            XCTAssertNotEqual(mainBundle.dropFirst("Main bundle: ".count), ownerBundle.dropFirst("Owner bundle: ".count))

            let output = try scan(project)
            XCTAssertFalse(output.contains("Unused localized string 'dynamic.used'"), output)
            XCTAssertFalse(output.contains("Unused localized string 'local.used'"), output)
            XCTAssertTrue(output.contains("Unused localized string 'owner.unused'"), output)
            XCTAssertTrue(output.contains("Unused localized string 'other.unused'"), output)
            XCTAssertTrue(output.contains("Unused localized string 'local.unused'"), output)
            XCTAssertTrue(output.contains("Unused localized string 'main.unused'"), output)
        }

        func testUnknownBundleWithoutPrefixRetainsAllCatalogKeys() throws {
            let project = try makeProject()
            defer { try? FileManager.default.removeItem(at: project) }
            let source = project.appendingPathComponent("Sources/Lookup/Lookup.swift")
            let contents = try String(contentsOf: source, encoding: .utf8)
            try contents.replacingOccurrences(of: "\"dynamic.\" + key.dropFirst(\"dynamic.\".count)", with: "key")
                .write(to: source, atomically: true, encoding: .utf8)

            let appOutput = try run(URL(fileURLWithPath: "/usr/bin/env"), ["swift", "run", "App"], in: project)
            XCTAssertTrue(appOutput.contains("Dynamic value"), appOutput)
            let output = try scan(project)
            XCTAssertTrue(output.contains("Periphery cannot report unused String Catalog keys."), output)
            XCTAssertFalse(output.contains("Unused localized string 'dynamic.used'"), output)
            XCTAssertFalse(output.contains("Unused localized string 'owner.unused'"), output)
            XCTAssertFalse(output.contains("Unused localized string 'other.unused'"), output)
            XCTAssertFalse(output.contains("Unused localized string 'main.unused'"), output)
            let quietOutput = try scan(project, quiet: true)
            XCTAssertTrue(quietOutput.contains("Periphery cannot report unused String Catalog keys."), quietOutput)
        }

        private func makeProject() throws -> URL {
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("CrossBundleProject")
            let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            for name in ["Package.swift", "Sources"] {
                try FileManager.default.copyItem(at: fixture.appendingPathComponent(name), to: project.appendingPathComponent(name))
            }
            return project
        }

        private func scan(_ project: URL, quiet: Bool = false) throws -> String {
            let bundle = try XCTUnwrap(Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") })
            let executable = bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("periphery")
            var arguments = ["scan", "--disable-update-check"]
            if quiet {
                arguments.append("--quiet")
            }
            arguments += ["--", "--build-system", "native"]
            return try run(executable, arguments, in: project)
        }

        private func run(_ executable: URL, _ arguments: [String], in directory: URL) throws -> String {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = try XCTUnwrap(pipe.fileHandleForReading.readToEnd())
            process.waitUntilExit()
            let output = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertEqual(process.terminationStatus, 0, output)
            return output
        }
    }
#endif
