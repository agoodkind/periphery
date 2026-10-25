//
//  release-tests.swift
//  Periphery
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-10-25
//

import CryptoKit
import Foundation

struct RegressionError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@discardableResult
func run(_ executable: String, _ arguments: [String], at directory: URL,
         environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String
{
    let output = directory.appendingPathComponent(UUID().uuidString)
    guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
        throw RegressionError("Cannot create the command output file")
    }

    let handle = try FileHandle(forWritingTo: output)
    defer {
        try? handle.close()
        try? FileManager.default.removeItem(at: output)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.currentDirectoryURL = directory
    var isolatedEnvironment = environment
    isolatedEnvironment["GIT_CONFIG_GLOBAL"] = "/dev/null"
    isolatedEnvironment["GIT_CONFIG_NOSYSTEM"] = "1"
    process.environment = isolatedEnvironment
    process.standardOutput = handle
    process.standardError = handle
    try process.run()
    process.waitUntilExit()
    let result = try String(contentsOf: output, encoding: .utf8)
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw RegressionError("\(executable) failed with status \(process.terminationStatus):\n\(result)")
    }

    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

func testHomebrewSigning(releaseScript: URL, formulaSource: URL) throws {
    let files = FileManager.default
    let formulaData = try Data(contentsOf: formulaSource)
    let temporary = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try files.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: temporary) }
    let origin = temporary.appendingPathComponent("origin.git", isDirectory: true)
    let tap = temporary.appendingPathComponent("homebrew-tap", isDirectory: true)
    try run("git", ["init", "--bare", "--initial-branch=main", origin.path], at: temporary)
    try run("git", ["clone", origin.path, tap.path], at: temporary)
    try run("git", ["config", "user.name", "Periphery release regression"], at: tap)
    try run("git", ["config", "user.email", "noreply@agoodkind.io"], at: tap)
    let formulaDirectory = tap.appendingPathComponent("Formula", isDirectory: true)
    try files.createDirectory(at: formulaDirectory, withIntermediateDirectories: true)
    try formulaData.write(to: formulaDirectory.appendingPathComponent("periphery.rb"))
    try run("git", ["add", "Formula/periphery.rb"], at: tap)
    try run("git", ["-c", "commit.gpgSign=false", "commit", "-m", "Initialize Homebrew formula"], at: tap)
    try run("git", ["push", "origin", "HEAD:main"], at: tap)

    let generatedKey = temporary.appendingPathComponent("generated-key")
    try run("ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-f", generatedKey.path], at: temporary)
    let privateKey = try String(contentsOf: generatedKey, encoding: .utf8).trimmingCharacters(in: .newlines)
    let invalidKey = temporary.appendingPathComponent("key-without-newline")
    try Data(privateKey.utf8).write(to: invalidKey)
    try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: invalidKey.path)
    let parser = Process()
    parser.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
    parser.arguments = ["-y", "-P", "", "-f", invalidKey.path]
    parser.standardOutput = FileHandle.nullDevice
    parser.standardError = FileHandle.nullDevice
    try parser.run()
    parser.waitUntilExit()
    guard parser.terminationReason == .exit, parser.terminationStatus != 0 else {
        throw RegressionError("ssh-keygen must reject the private key without its trailing newline")
    }

    print("ssh-keygen rejected the private key without its trailing newline with status \(parser.terminationStatus)")
    let publicKey = try String(contentsOf: generatedKey.appendingPathExtension("pub"), encoding: .utf8)
    let allowedSigners = temporary.appendingPathComponent("allowed-signers")
    try ("noreply@agoodkind.io " + publicKey).write(to: allowedSigners, atomically: true, encoding: .utf8)

    let version = "3.8.0-agoodkind.4"
    let archiveName = "periphery-\(version)-macos-arm64.zip"
    let release = temporary.appendingPathComponent("release", isDirectory: true)
    try files.createDirectory(at: release, withIntermediateDirectories: true)
    let archive = release.appendingPathComponent(archiveName)
    try run("zip", ["-q", archive.path, "periphery.rb"], at: formulaDirectory)
    let archiveData = try Data(contentsOf: archive)
    let digest = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()

    var environment = ProcessInfo.processInfo.environment
    environment["VERSION"] = version
    environment["GITHUB_REPOSITORY"] = "agoodkind/periphery"
    environment["HOMEBREW_TAP_DEPLOY_KEY"] = privateKey
    environment["SIGNING_KEY_PATH"] = temporary.appendingPathComponent("release-signing-key").path
    try run("swift", [releaseScript.path, "homebrew"], at: temporary, environment: environment)

    let pushed = try run("git", ["--git-dir", origin.path, "show", "refs/heads/main:Formula/periphery.rb"], at: temporary)
    let downloadURL = "https://github.com/agoodkind/periphery/releases/download/\(version)/\(archiveName)"
    guard pushed.contains("\n  version \"\(version)\"\n") else {
        throw RegressionError("The pushed Homebrew formula must use the release version")
    }
    guard pushed.contains("\n  url \"\(downloadURL)\"\n") else {
        throw RegressionError("The pushed Homebrew formula must download the release archive")
    }
    guard pushed.contains("\n  sha256 \"\(digest)\"\n") else {
        throw RegressionError("The pushed Homebrew formula must contain the archive checksum")
    }

    try run("git", ["--git-dir", origin.path, "-c", "gpg.format=ssh", "-c", "gpg.ssh.allowedSignersFile=\(allowedSigners.path)", "verify-commit", "refs/heads/main"], at: temporary)
    print("Homebrew signed publication passed with a private key that omits its trailing newline")
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw RegressionError("Usage: swift release-tests.swift RELEASE_SCRIPT FORMULA_PATH")
    }

    try testHomebrewSigning(releaseScript: URL(fileURLWithPath: CommandLine.arguments[1]),
                            formulaSource: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(EXIT_FAILURE)
}
