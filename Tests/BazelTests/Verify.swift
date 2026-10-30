#!/usr/bin/env swift

import Foundation

struct Finding: Decodable {
    let name: String
}

struct Fixture {
    let name: String
    let source: URL
    let files: [String]
    let unusedFiles: [String]
    let expectedNames: [String]
    let catalog: String?
    let setupTag: String?
    let targetedQuery: String?
    let targetedNames: [String]
}

enum VerificationError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

func report(_ message: String) {
    FileHandle.standardOutput.write(Data("\(message)\n".utf8))
}

func run(_ arguments: [String], in directory: URL, log: URL, input: String? = nil) throws -> Int32 {
    let output = try FileHandle(forWritingTo: log)
    defer { output.closeFile() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["bazel"] + arguments
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = output
    let inputPipe = Pipe()
    if input != nil {
        process.standardInput = inputPipe
    }
    try process.run()
    if let input {
        try inputPipe.fileHandleForWriting.write(contentsOf: Data(input.utf8))
        try inputPipe.fileHandleForWriting.close()
    }
    process.waitUntilExit()
    return process.terminationStatus
}

func scan(in directory: URL, results: URL, log: URL, query: String? = nil) throws -> Int32 {
    var arguments = [
        "run", "@periphery", "--", "scan", "--bazel", "--strict",
        "--format", "json", "--disable-update-check", "--write-results", results.path,
    ]
    if let query {
        arguments.append(contentsOf: ["--bazel-query", query])
    }
    return try run(
        arguments,
        in: directory,
        log: log
    )
}

func names(in results: URL) throws -> [String] {
    try JSONDecoder().decode([Finding].self, from: Data(contentsOf: results)).map(\.name).sorted()
}

func verifySetup(_ fixtureSpec: Fixture, fixture: URL, tag: String, responses: String, indicator: String, log: URL, results: URL) throws {
    let status = try run(
        [
            "run", "@periphery", "--", "scan", "--setup", "--strict", "--format", "json",
            "--disable-update-check", "--no-color", "--write-results", results.path,
        ],
        in: fixture,
        log: log,
        input: responses
    )
    guard status == 1, FileManager.default.fileExists(atPath: results.path) else {
        throw VerificationError.failed("Guided setup must finish its strict scan; received exit \(status). Log: \(log.path)")
    }

    let output = try String(contentsOf: log, encoding: .utf8)
    let foundNames = try names(in: results)
    let requiredOutput = [
        indicator,
        "bazel_dep(name = \"periphery\", version = \"3.8.0\")",
        "git_override(",
        "module_name = \"periphery\"",
        "remote = \"https://github.com/agoodkind/periphery.git\"",
        "tag = \"\(tag)\"",
        "use_repo(use_extension(\"@periphery//bazel:generated.bzl\", \"generated\"), \"periphery_generated\")",
        "periphery scan",
        "--bazel",
    ]
    guard foundNames == fixtureSpec.expectedNames, requiredOutput.allSatisfy(output.contains) else {
        throw VerificationError.failed("Guided setup must show the fork configuration and report \(fixtureSpec.expectedNames); received \(foundNames). Log: \(log.path)")
    }
}

func verify(_ fixtureSpec: Fixture, repository: URL) throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory.appendingPathComponent("periphery-bazel-\(UUID().uuidString)")
    let fixture = temporary.appendingPathComponent("Fixture")
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    try manager.createDirectory(at: fixture, withIntermediateDirectories: true)
    for path in fixtureSpec.files {
        try manager.copyItem(
            at: fixtureSpec.source.appendingPathComponent(path),
            to: fixture.appendingPathComponent(path)
        )
    }
    try manager.copyItem(
        at: repository.appendingPathComponent(".bazelversion"),
        to: fixture.appendingPathComponent(".bazelversion")
    )

    let module = fixture.appendingPathComponent("MODULE.bazel")
    let source = try String(contentsOf: module, encoding: .utf8)
    guard source.contains("path = \"../../..\"") else {
        throw VerificationError.failed("The fixture must select the local Periphery checkout.")
    }

    let repositoryPath = repository.path.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    try source.replacingOccurrences(of: "path = \"../../..\"", with: "path = \"\(repositoryPath)\"")
        .write(to: module, atomically: true, encoding: .utf8)

    let unusedLog = temporary.appendingPathComponent("unused.log")
    let cleanLog = temporary.appendingPathComponent("clean.log")
    let catalogLog = temporary.appendingPathComponent("catalog.log")
    let cleanupLog = temporary.appendingPathComponent("cleanup.log")
    let setupLog = temporary.appendingPathComponent("setup.log")
    let linkedSetupLog = temporary.appendingPathComponent("linked-setup.log")
    let directorySetupLog = temporary.appendingPathComponent("directory-setup.log")
    let targetedLog = temporary.appendingPathComponent("targeted.log")
    let targetedCleanLog = temporary.appendingPathComponent("targeted-clean.log")
    for log in [unusedLog, cleanLog, catalogLog, cleanupLog, setupLog, linkedSetupLog, directorySetupLog, targetedLog, targetedCleanLog] {
        guard manager.createFile(atPath: log.path, contents: nil) else {
            throw VerificationError.failed("Could not create \(log.path)")
        }
    }

    do {
        if let tag = fixtureSpec.setupTag {
            let setupResults = temporary.appendingPathComponent("setup.json")
            report("Running guided setup for \(fixtureSpec.name).")
            try verifySetup(
                fixtureSpec, fixture: fixture, tag: tag, responses: "\(tag)\n\nn\nn\n",
                indicator: "Detected Bazel project",
                log: setupLog,
                results: setupResults
            )
            report("Guided setup showed the fork configuration and the strict scan reported \(fixtureSpec.expectedNames).")

            let xcodeFixture = repository.appendingPathComponent("Tests/XcodeTests/SwiftUIProject")
            let linkedProject = temporary.appendingPathComponent("LinkedProject")
            let projectLink = fixture.appendingPathComponent("bazel-project")
            try manager.copyItem(at: xcodeFixture, to: linkedProject)
            try manager.createSymbolicLink(at: projectLink, withDestinationURL: linkedProject)
            try verifySetup(
                fixtureSpec, fixture: fixture, tag: tag, responses: "2\n\(tag)\n\nn\nn\n",
                indicator: "1 Xcode\n2 Bazel", log: linkedSetupLog,
                results: temporary.appendingPathComponent("linked-setup.json")
            )
            try manager.removeItem(at: projectLink)

            let projectDirectory = fixture.appendingPathComponent("Project")
            try manager.copyItem(at: xcodeFixture, to: projectDirectory)
            try verifySetup(
                fixtureSpec, fixture: fixture, tag: tag, responses: "2\n\(tag)\n\nn\nn\n",
                indicator: "1 Xcode\n2 Bazel", log: directorySetupLog,
                results: temporary.appendingPathComponent("directory-setup.json")
            )
            try manager.removeItem(at: projectDirectory)
            report("Guided setup also detected a real Xcode project through a symlink and a regular directory.")
        }

        let unusedResults = temporary.appendingPathComponent("unused.json")
        report("Scanning \(fixtureSpec.name) with its unused declaration.")
        let unusedStatus = try scan(in: fixture, results: unusedResults, log: unusedLog)
        let unusedNames = try names(in: unusedResults)
        guard unusedStatus == 1, unusedNames == fixtureSpec.expectedNames else {
            throw VerificationError.failed("Expected exit 1 and \(fixtureSpec.expectedNames); received exit \(unusedStatus), \(unusedNames). Log: \(unusedLog.path)")
        }

        report("The strict scan returned 1 and reported \(unusedNames).")

        if let query = fixtureSpec.targetedQuery {
            let results = temporary.appendingPathComponent("targeted.json")
            let status = try scan(in: fixture, results: results, log: targetedLog, query: query)
            let found = try names(in: results)
            guard status == 1, found == fixtureSpec.targetedNames else {
                throw VerificationError.failed("Expected exit 1 and \(fixtureSpec.targetedNames); received exit \(status), \(found). Log: \(targetedLog.path)")
            }

            report("The app-only scan returned 1 and reported \(found).")
        }

        for path in fixtureSpec.unusedFiles {
            try manager.removeItem(at: fixture.appendingPathComponent(path))
        }
        let cleanResults = temporary.appendingPathComponent("clean.json")
        report("Scanning the fixture after removing its unused declaration.")
        let cleanStatus = try scan(in: fixture, results: cleanResults, log: cleanLog)
        let cleanNames = try names(in: cleanResults)
        guard cleanStatus == 0, cleanNames.isEmpty else {
            throw VerificationError.failed("Expected exit 0 without findings; received exit \(cleanStatus), \(cleanNames). Log: \(cleanLog.path)")
        }

        report("The clean scan returned 0 without findings.")

        if let query = fixtureSpec.targetedQuery {
            let results = temporary.appendingPathComponent("targeted-clean.json")
            let status = try scan(in: fixture, results: results, log: targetedCleanLog, query: query)
            let found = try names(in: results)
            guard status == 0, found.isEmpty else {
                throw VerificationError.failed("Expected app-only exit 0 without findings; received exit \(status), \(found). Log: \(targetedCleanLog.path)")
            }

            report("The app-only clean scan returned 0 without findings.")
        }

        if let catalog = fixtureSpec.catalog {
            let catalogPath = fixture.appendingPathComponent(catalog)
            try "{".write(to: catalogPath, atomically: true, encoding: .utf8)
            let catalogResults = temporary.appendingPathComponent("catalog.json")
            let catalogStatus = try scan(in: fixture, results: catalogResults, log: catalogLog)
            let catalogOutput = try String(contentsOf: catalogLog, encoding: .utf8)
            guard catalogStatus != 0, catalogOutput.contains("Failed to read String Catalog") else {
                throw VerificationError.failed("The scan must report the invalid String Catalog. Log: \(catalogLog.path)")
            }

            report("The scan reported the invalid String Catalog.")
        }
    } catch {
        let cleanupStatus = try run(["clean", "--expunge"], in: fixture, log: cleanupLog)
        if cleanupStatus != 0 {
            report("Bazel cleanup failed with exit \(cleanupStatus). Log: \(cleanupLog.path)")
        }
        throw VerificationError.failed("\(error)\nVerification evidence remains at \(temporary.path)")
    }

    let cleanupStatus = try run(["clean", "--expunge"], in: fixture, log: cleanupLog)
    guard cleanupStatus == 0 else {
        throw VerificationError.failed("Bazel cleanup failed with exit \(cleanupStatus). Log: \(cleanupLog.path)")
    }

    try manager.removeItem(at: temporary)
    report("Bazel consumer verification passed, and the temporary workspace was removed.")
}

do {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repository = tests.deletingLastPathComponent().deletingLastPathComponent()
    let fixtures = [
        Fixture(
            name: "the Swift executable",
            source: tests.appendingPathComponent("Fixture"),
            files: ["MODULE.bazel", "BUILD.bazel", "Sources"],
            unusedFiles: ["Sources/Unused.swift"],
            expectedNames: ["unusedGreeting()"],
            catalog: nil,
            setupTag: "3.9.3-agoodkind.1",
            targetedQuery: nil,
            targetedNames: []
        ),
        Fixture(
            name: "the Apple applications",
            source: repository.appendingPathComponent("Tests/BazelAppleTests/Fixture"),
            files: ["MODULE.bazel", "BUILD.bazel", "Sources", "Private", "IOS", "TVOS", "WatchOS", "VisionOS", "EmbeddedFramework", "EmbeddedService", "Info.plist", "Info-iOS.plist", "Localizable.xcstrings"],
            unusedFiles: ["Sources/Unused.swift", "Private/Unused.swift", "IOS/Unused.swift", "TVOS/Unused.swift", "WatchOS/Unused.swift", "VisionOS/Unused.swift", "EmbeddedFramework/Unused.swift", "EmbeddedService/Unused.swift"],
            expectedNames: ["unusedEmbeddedFrameworkControl()", "unusedEmbeddedServiceControl()", "unusedGreeting()", "unusedIOSGreeting()", "unusedPrivateGreeting()", "unusedTVOSControl()", "unusedVisionOSControl()", "unusedWatchOSControl()"],
            catalog: "Localizable.xcstrings",
            setupTag: nil,
            targetedQuery: "//:app",
            targetedNames: ["unusedEmbeddedFrameworkControl()", "unusedEmbeddedServiceControl()", "unusedGreeting()", "unusedPrivateGreeting()"]
        ),
    ]
    for fixture in fixtures {
        try verify(fixture, repository: repository)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
