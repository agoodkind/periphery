#!/usr/bin/env swift

import Foundation

struct Finding: Decodable {
    let name: String
    let modules: [String]
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

func run(_ arguments: [String], in directory: URL, log: URL) throws -> Int32 {
    let output = try FileHandle(forWritingTo: log)
    defer { output.closeFile() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["bazel"] + arguments
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func verify() throws {
    let manager = FileManager.default
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let temporary = manager.temporaryDirectory.appendingPathComponent("periphery-proto-\(UUID().uuidString)")
    let fixture = tests.appendingPathComponent("Fixture")
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)

    let log = temporary.appendingPathComponent("scan.log")
    let cleanupLog = temporary.appendingPathComponent("cleanup.log")
    let results = temporary.appendingPathComponent("findings.json")
    for file in [log, cleanupLog] {
        guard manager.createFile(atPath: file.path, contents: nil) else {
            throw VerificationError.failed("Could not create \(file.path)")
        }
    }

    report("Scanning the independent proto and Swift control targets through Bazel.")
    do {
        let status = try run(
            [
                "run", "@periphery", "--", "scan", "--bazel", "--strict", "--verbose",
                "--format", "json", "--disable-update-check", "--write-results", results.path,
            ],
            in: fixture,
            log: log
        )
        let findings = try JSONDecoder().decode([Finding].self, from: Data(contentsOf: results))
        let names = Set(findings.map(\.name))
        guard status == 1, names.contains("unusedControl()"), !names.contains("usedControl()"), !names.contains("ControlApplication") else {
            throw VerificationError.failed("The strict scan must report the unused control and preserve the used control. Exit: \(status); findings: \(names.sorted()).")
        }

        let sentinel = "_GeneratedWithProtocGenSwiftVersion"
        guard !findings.contains(where: { $0.name == sentinel && $0.modules.contains("ProtoFixture") }) else {
            throw VerificationError.failed("The scan reported the required SwiftProtobuf compatibility check as unused.")
        }
        guard findings.contains(where: { $0.name == sentinel && $0.modules.contains("control") }) else {
            throw VerificationError.failed("The scan retained the unrelated user type with the compatibility check's name.")
        }
        guard findings.contains(where: { $0.name == "ProtoOnlyMessage" && $0.modules.contains("ProtoFixture") }) else {
            throw VerificationError.failed("The scan did not report the genuinely unused generated message.")
        }

        let output = try String(contentsOf: log, encoding: .utf8)
        let rows = output.split(separator: "\n")
        for phase in ["one", "two"] {
            guard rows.contains(where: { $0.contains("[index:swift:phase:\(phase)]") && $0.contains("message.pb.swift (ProtoFixture)") }) else {
                throw VerificationError.failed("Default discovery did not index the generated proto source during phase \(phase).")
            }
        }
        guard !rows.contains(where: { $0.contains("[index:swift:phase:") && $0.contains("(SwiftProtobuf)") }) else {
            throw VerificationError.failed("The scan indexed external SwiftProtobuf dependency sources.")
        }

        report("The scan indexed ProtoFixture in both phases and preserved its compatibility check.")
        report("The unused message, unused control function, and similarly named user type remained findings; the strict scan returned 1.")
    } catch {
        let status = try run(["shutdown"], in: fixture, log: cleanupLog)
        if status != 0 {
            report("Bazel cleanup failed with exit \(status). Log: \(cleanupLog.path)")
        }
        throw VerificationError.failed("\(error)\nEvidence remains at \(temporary.path)")
    }
    let status = try run(["shutdown"], in: fixture, log: cleanupLog)
    guard status == 0 else {
        throw VerificationError.failed("Bazel cleanup failed with exit \(status). Log: \(cleanupLog.path)")
    }

    try manager.removeItem(at: temporary)
    report("Proto discovery verification passed, and its temporary diagnostics were removed.")
}

do {
    try verify()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
