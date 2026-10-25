//
//  release.swift
//  Periphery
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-10-25
//

import CryptoKit
import Foundation

struct ReleaseError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

nonisolated var files: FileManager { FileManager.default }
let environment = ProcessInfo.processInfo.environment

func required(_ name: String, allowEmpty: Bool = false) throws -> String {
    guard let value = environment[name], allowEmpty || !value.isEmpty else {
        throw ReleaseError("Set \(name) before running the release command")
    }

    return value
}

enum ProcessOutput {
    case inherit
    case capture
    case captureWithError
}

@discardableResult
func run(_ executable: String, _ arguments: [String], at directory: URL? = nil,
         outputMode: ProcessOutput = .inherit) throws -> String
{
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.currentDirectoryURL = directory
    let output = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var handle: FileHandle?
    if outputMode != .inherit {
        guard files.createFile(atPath: output.path, contents: nil) else {
            throw ReleaseError("Cannot create the command output file")
        }

        handle = try FileHandle(forWritingTo: output)
        process.standardOutput = handle
        if outputMode == .captureWithError { process.standardError = handle }
    }
    defer {
        try? handle?.close()
        if outputMode != .inherit { try? files.removeItem(at: output) }
    }
    try process.run()
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw ReleaseError("\(executable) failed with status \(process.terminationStatus)")
    }

    if outputMode != .inherit {
        return try String(contentsOf: output, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return ""
}

func append(_ value: String, to variable: String) throws {
    let path = try required(variable)
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(value.utf8))
}

func replace(_ pattern: String, with replacement: String, in url: URL) throws {
    let text = try String(contentsOf: url, encoding: .utf8)
    let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
    let range = NSRange(text.startIndex..., in: text)
    guard regex.numberOfMatches(in: text, range: range) == 1 else {
        throw ReleaseError("\(url.path) must contain exactly one match for \(pattern)")
    }

    let result = regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    try result.write(to: url, atomically: true, encoding: .utf8)
}

func privateFile(_ value: Data, at url: URL) throws {
    try value.write(to: url, options: .atomic)
    try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

func checksum(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 65536), !data.isEmpty {
        hash.update(data: data)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

struct Asset: Decodable {
    let id: Int
    let name: String
    let browser_download_url: URL
}

struct GitHubRelease: Decodable {
    let id: Int
    let tag_name: String
    let draft: Bool
    let assets: [Asset]
}

struct Entitlements: Decodable {
    let disableLibraryValidation: Bool
    enum CodingKeys: String, CodingKey {
        case disableLibraryValidation = "com.apple.security.cs.disable-library-validation"
    }
}

struct GitHub {
    let repository: String
    let token: String?

    init(repository: String, token: String?) {
        self.repository = repository
        if let token, !token.isEmpty {
            self.token = token
        } else {
            self.token = nil
        }
    }

    func request(_ path: String, method: String = "GET", body: Data? = nil,
                 contentType: String = "application/json", host: String = "api.github.com") async throws -> Data
    {
        guard let url = URL(string: "https://\(host)/\(path)") else {
            throw ReleaseError("Invalid GitHub API path")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Periphery-release", forHTTPHeaderField: "User-Agent")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if method != "GET" {
            throw ReleaseError("Set GH_TOKEN before publishing a release")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ReleaseError("GitHub did not return an HTTP response")
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw ReleaseError("GitHub API \(method) \(path) failed with HTTP \(response.statusCode)")
        }

        return data
    }

    func release(_ version: String) async throws -> GitHubRelease? {
        var page = 1
        while true {
            let data = try await request("repos/\(repository)/releases?per_page=100&page=\(page)")

            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            if let release = releases.first(where: { $0.tag_name == version }) { return release }
            if releases.count < 100 { return nil }
            page += 1
        }
    }

    func send(_ path: String, method: String, value: some Encodable) async throws -> Data {
        try await request(path, method: method, body: JSONEncoder().encode(value))
    }
}

struct ReleaseContext {
    let version: String
    let root: URL
    let directory: URL
    let github: GitHub

    init() throws {
        version = try required("VERSION")
        guard Self.suffix(version) != nil else { throw ReleaseError("VERSION must match 3.8.0-agoodkind.N") }

        root = URL(fileURLWithPath: files.currentDirectoryPath, isDirectory: true)
        directory = root.appendingPathComponent("release", isDirectory: true)
        github = try GitHub(repository: required("GITHUB_REPOSITORY"), token: environment["GH_TOKEN"])
    }

    static func suffix(_ tag: String) -> Int? {
        let prefix = "3.8.0-agoodkind."
        guard tag.hasPrefix(prefix) else { return nil }

        let suffix = tag.dropFirst(prefix.count)
        guard !suffix.isEmpty, suffix.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }

        return Int(suffix)
    }

    var archiveName: String { "periphery-\(version)-macos-arm64.zip" }
    var diskImage: URL { directory.appendingPathComponent("periphery-\(version)-macos-arm64.dmg") }
    var product: URL { directory.appendingPathComponent("periphery-\(version)", isDirectory: true) }
    var assetNames: [String] {
        [archiveName, diskImage.lastPathComponent, "install.sh", "checksums.txt"]
    }

    func checkRelease() async throws {
        if let release = try await github.release(version), !release.draft {
            let names = Set(release.assets.map(\.name))
            for name in assetNames where !names.contains(name) {
                throw ReleaseError("Published release \(version) lacks \(name). Dispatch with an empty tag to create a complete release.")
            }
            try append("exists=true\n", to: "GITHUB_OUTPUT")
            print("Reusing published release \(version)")
        } else {
            try append("exists=false\n", to: "GITHUB_OUTPUT")
        }
    }

    func build() throws {
        try run(required("SWIFT_COMMAND"), ["build", "-c", "release", "--arch", "arm64", "--product", "periphery", "--scratch-path", ".build/arm64"])
        try files.createDirectory(at: product, withIntermediateDirectories: true)
        try files.copyItem(at: root.appendingPathComponent(".build/arm64/release/periphery"), to: product.appendingPathComponent("periphery"))
        let swiftPath = try run("xcrun", ["--find", "swift"], outputMode: .capture)
        let library = URL(fileURLWithPath: swiftPath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/libIndexStore.dylib")
        try files.copyItem(at: library, to: product.appendingPathComponent("libIndexStore.dylib"))
        let binary = product.appendingPathComponent("periphery").path
        guard try run("lipo", ["-archs", binary], outputMode: .capture) == "arm64" else {
            throw ReleaseError("The release executable must contain only arm64 code")
        }

        try run("lipo", [product.appendingPathComponent("libIndexStore.dylib").path, "-verify_arch", "arm64"])
        guard try run(binary, ["version"], outputMode: .capture) == version else {
            throw ReleaseError("The executable version must equal \(version)")
        }
    }

    func package() throws {
        let identity = try required("SIGNING_IDENTITY")
        guard let match = identity.range(of: #"\([A-Z0-9]{10}\)$"#, options: .regularExpression) else {
            throw ReleaseError("Unable to read Team ID from signing identity")
        }

        let team = identity[match].dropFirst().dropLast()
        let binary = product.appendingPathComponent("periphery").path
        let library = product.appendingPathComponent("libIndexStore.dylib").path
        try run("codesign", ["--force", "--options", "runtime", "--timestamp", "--sign", identity, library])
        try run("codesign", ["--force", "--options", "runtime", "--timestamp", "--entitlements", required("ENTITLEMENTS_PATH"), "--sign", identity, binary])
        try run("codesign", ["--verify", "--deep", "--strict", "--verbose=2", binary])
        try run("codesign", ["--verify", "--strict", "--verbose=2", library])
        let details = try run("codesign", ["--display", "--verbose=4", binary], outputMode: .captureWithError)
        guard details.contains("TeamIdentifier=\(team)"), details.contains("Timestamp="),
              details.range(of: #"(?m)^CodeDirectory .* flags=.*runtime"#, options: .regularExpression) != nil
        else {
            throw ReleaseError("The signature must include the expected Team ID, timestamp, and hardened runtime")
        }

        let entitlements = try run("codesign", ["--display", "--entitlements", "-", "--xml", binary], outputMode: .capture)
        let decoded = try PropertyListDecoder().decode(Entitlements.self, from: Data(entitlements.utf8))
        guard decoded.disableLibraryValidation else { throw ReleaseError("Library validation entitlement is missing") }

        try details.write(toFile: required("SIGNATURE_DETAILS_PATH"), atomically: true, encoding: .utf8)
        try entitlements.write(toFile: required("SIGNED_ENTITLEMENTS_PATH"), atomically: true, encoding: .utf8)
        try run(binary, ["version"])
        try run("ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", product.path, directory.appendingPathComponent(archiveName).path])
        try run("hdiutil", ["create", "-volname", "Periphery \(version)", "-srcfolder", product.path, "-format", "UDZO", diskImage.path])
        try run("codesign", ["--force", "--timestamp", "--sign", identity, diskImage.path])
        try run("codesign", ["--verify", "--strict", "--verbose=2", diskImage.path])
    }

    func notarize() throws {
        let key = try URL(fileURLWithPath: required("NOTARY_KEY_PATH"))
        try privateFile(Data(required("NOTARY_KEY").utf8), at: key)
        defer { try? files.removeItem(at: key) }
        try run("xcrun", ["notarytool", "submit", diskImage.path, "--key", key.path, "--key-id", required("NOTARY_KEY_ID"), "--issuer", required("NOTARY_ISSUER_ID"), "--wait"])
        try run("xcrun", ["stapler", "staple", diskImage.path])
        try run("xcrun", ["stapler", "validate", diskImage.path])
        try run("spctl", ["--assess", "--type", "open", "--context", "context:primary-signature", "-v", diskImage.path])
    }

    func checksums() throws {
        try files.copyItem(at: root.appendingPathComponent("scripts/install.sh"), to: directory.appendingPathComponent("install.sh"))
        let lines = try assetNames.dropLast().map { name in
            try "\(checksum(directory.appendingPathComponent(name)))  \(name)\n"
        }.joined()
        try lines.write(to: directory.appendingPathComponent("checksums.txt"), atomically: true, encoding: .utf8)
    }

    func publish() async throws {
        let source = try required("SOURCE_SHA")
        let tags = try run("git", ["tag", "--list", version], outputMode: .capture)
        if tags.isEmpty {
            try run("git", ["tag", version, source])
        } else {
            guard try run("git", ["rev-parse", "\(version)^{commit}"], outputMode: .capture) == source else {
                throw ReleaseError("Tag \(version) does not match source commit \(source)")
            }
        }
        try run("git", ["push", "origin", "refs/tags/\(version)"])
        let release: GitHubRelease
        if let existing = try await github.release(version) {
            guard existing.draft else { throw ReleaseError("Published release assets cannot change") }

            release = existing
        } else {
            struct NotesRequest: Encodable { let tag_name: String; let target_commitish: String }
            struct Notes: Decodable { let body: String }
            let notesData = try await github.send("repos/\(github.repository)/releases/generate-notes", method: "POST", value: NotesRequest(tag_name: version, target_commitish: source))
            let notes = try JSONDecoder().decode(Notes.self, from: notesData)
            struct Create: Encodable {
                let tag_name: String; let name: String; let body: String
                let draft = true
            }
            let data = try await github.send("repos/\(github.repository)/releases", method: "POST", value: Create(tag_name: version, name: "Periphery \(version)", body: notes.body))
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        }
        for name in assetNames {
            if let asset = release.assets.first(where: { $0.name == name }) {
                _ = try await github.request("repos/\(github.repository)/releases/assets/\(asset.id)", method: "DELETE")
            }
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            _ = try await github.request("repos/\(github.repository)/releases/\(release.id)/assets?name=\(name)", method: "POST", body: data, contentType: "application/octet-stream", host: "uploads.github.com")
        }
        struct Publish: Encodable { let draft = false; let make_latest = "true" }
        _ = try await github.send("repos/\(github.repository)/releases/\(release.id)", method: "PATCH", value: Publish())
    }

    func download() async throws {
        guard let release = try await github.release(version), !release.draft else {
            throw ReleaseError("Published release \(version) does not exist")
        }

        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in [archiveName, "checksums.txt"] {
            guard let asset = release.assets.first(where: { $0.name == name }) else {
                throw ReleaseError("Release \(version) lacks \(name)")
            }

            let (temporary, response) = try await URLSession.shared.download(from: asset.browser_download_url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw ReleaseError("Cannot download release asset \(name)")
            }

            try files.moveItem(at: temporary, to: directory.appendingPathComponent(name))
        }
        let text = try String(contentsOf: directory.appendingPathComponent("checksums.txt"), encoding: .utf8)
        let expected = text.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count == 2 && fields[1] == archiveName ? String(fields[0]) : nil
        }
        guard expected.count == 1, try checksum(directory.appendingPathComponent(archiveName)) == expected[0] else {
            throw ReleaseError("Checksum verification failed for \(archiveName)")
        }

        print("\(archiveName): OK")
    }

    func homebrew() throws {
        let tap = root.appendingPathComponent("homebrew-tap", isDirectory: true)
        let formula = tap.appendingPathComponent("Formula/periphery.rb")
        let digest = try checksum(directory.appendingPathComponent(archiveName))
        let url = "https://github.com/agoodkind/periphery/releases/download/\(version)/\(archiveName)"
        try replace(#"^  url ".*"$"#, with: "  url \"\(url)\"", in: formula)
        try replace(#"^  version ".*"$"#, with: "  version \"\(version)\"", in: formula)
        try replace(#"^  sha256 ".*"$"#, with: "  sha256 \"\(digest)\"", in: formula)
        try run("ruby", ["-c", formula.path])
        let key = try URL(fileURLWithPath: required("SIGNING_KEY_PATH"))
        let publicKey = key.appendingPathExtension("pub")
        let secret = try required("HOMEBREW_TAP_DEPLOY_KEY").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        try privateFile(Data(secret.utf8), at: key)
        defer {
            try? files.removeItem(at: key)
            try? files.removeItem(at: publicKey)
        }
        let publicValue = try run("ssh-keygen", ["-y", "-P", "", "-f", key.path], outputMode: .capture)
        try (publicValue + "\n").write(to: publicKey, atomically: true, encoding: .utf8)
        for (name, value) in [
            ("user.name", "Periphery release automation"), ("user.email", "noreply@agoodkind.io"),
            ("gpg.format", "ssh"), ("user.signingkey", key.path),
        ] {
            try run("git", ["config", name, value], at: tap)
        }
        try run("git", ["add", "Formula/periphery.rb"], at: tap)
        if try run("git", ["diff", "--cached", "--name-only"], at: tap, outputMode: .capture).isEmpty {
            print("Homebrew formula already matches \(version)")
            return
        }
        try run("git", ["commit", "-S", "-m", "Update Periphery to \(version)"], at: tap)
        try run("git", ["push", "origin", "HEAD:main"], at: tap)
    }
}

func prepare() throws {
    let source = try required("SOURCE_SHA", allowEmpty: true)
    let requested = try required("REQUESTED_TAG", allowEmpty: true)
    let head = try run("git", ["rev-parse", "HEAD"], outputMode: .capture)
    guard source.isEmpty || source == head else { throw ReleaseError("SOURCE_SHA must equal the checked-out commit \(head)") }

    let tags = try run("git", ["tag", "--list", "3.8.0-agoodkind.*"], outputMode: .capture).split(separator: "\n").map(String.init)
    let version: String
    if !requested.isEmpty {
        guard ReleaseContext.suffix(requested) != nil, tags.contains(requested) else {
            throw ReleaseError("REQUESTED_TAG must select an existing 3.8.0-agoodkind.N tag")
        }
        guard try run("git", ["rev-parse", "\(requested)^{commit}"], outputMode: .capture) == head else {
            throw ReleaseError("Requested release tag must identify the checked-out commit")
        }

        version = requested
    } else {
        var maximum = 0
        var matched: (suffix: Int, tag: String)?
        for tag in tags {
            guard let suffix = ReleaseContext.suffix(tag) else { continue }

            maximum = max(maximum, suffix)
            if try run("git", ["rev-parse", "\(tag)^{commit}"], outputMode: .capture) == head,
               suffix > (matched?.suffix ?? -1)
            {
                matched = (suffix, tag)
            }
        }
        guard maximum < Int.max else { throw ReleaseError("The release version suffix exceeds the supported range") }

        version = matched?.tag ?? "3.8.0-agoodkind.\(maximum + 1)"
    }
    let root = URL(fileURLWithPath: files.currentDirectoryPath)
    try replace(#"^let PeripheryVersion = ".*"$"#, with: "let PeripheryVersion = \"\(version)\"", in: root.appendingPathComponent("Sources/Frontend/Version.swift"))
    try replace("^VERSION=.*$", with: "VERSION=\(version)", in: root.appendingPathComponent("scripts/install.sh"))
    try append("version=\(version)\nsource_sha=\(head)\n", to: "GITHUB_OUTPUT")
    try append("VERSION=\(version)\n", to: "GITHUB_ENV")
}

func importCertificate() throws {
    guard let certificate = try Data(base64Encoded: required("DEVELOPER_ID_APPLICATION_CERTIFICATE"), options: .ignoreUnknownCharacters) else {
        throw ReleaseError("DEVELOPER_ID_APPLICATION_CERTIFICATE must contain a base64 certificate")
    }

    let path = try URL(fileURLWithPath: required("CERTIFICATE_PATH"))
    try privateFile(certificate, at: path)
    defer { try? files.removeItem(at: path) }
    let keychain = try required("KEYCHAIN_PATH")
    let password = try required("KEYCHAIN_PASSWORD")
    try run("security", ["create-keychain", "-p", password, keychain])
    try run("security", ["set-keychain-settings", "-lut", "21600", keychain])
    try run("security", ["unlock-keychain", "-p", password, keychain])
    try run("security", ["import", path.path, "-k", keychain, "-P", required("DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD"), "-T", "/usr/bin/codesign"])
    try run("security", ["list-keychain", "-d", "user", "-s", keychain])
    try run("security", ["set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", password, keychain])
}

do {
    guard CommandLine.arguments.count == 2 else { throw ReleaseError("Usage: swift release.swift COMMAND") }

    let command = CommandLine.arguments[1]
    switch command {
    case "prepare": try prepare()
    case "import-certificate": try importCertificate()
    default:
        let context = try ReleaseContext()
        switch command {
        case "check-release": try await context.checkRelease()
        case "build": try context.build()
        case "package": try context.package()
        case "notarize": try context.notarize()
        case "checksums": try context.checksums()
        case "publish": try await context.publish()
        case "download": try await context.download()
        case "homebrew": try context.homebrew()
        default: throw ReleaseError("Unknown release command: \(command)")
        }
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(EXIT_FAILURE)
}
