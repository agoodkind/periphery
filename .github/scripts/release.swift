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
    case file(URL)
}

@discardableResult
func run(_ executable: String, _ arguments: [String], at directory: URL? = nil,
         outputMode: ProcessOutput = .inherit, extraEnvironment: [String: String] = [:]) throws -> String
{
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.environment = environment.merging(extraEnvironment) { _, new in new }
    process.currentDirectoryURL = directory
    var capturedOutput: URL?
    let output: URL?
    switch outputMode {
    case .inherit:
        output = nil
    case .capture, .captureWithError:
        let temporary = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        output = temporary
        capturedOutput = temporary
    case let .file(destination):
        output = destination
    }
    var handle: FileHandle?
    if let output {
        guard files.createFile(atPath: output.path, contents: nil) else {
            throw ReleaseError("Cannot create command output file \(output.path)")
        }

        handle = try FileHandle(forWritingTo: output)
        process.standardOutput = handle
        if case .captureWithError = outputMode { process.standardError = handle }
    }
    defer {
        try? handle?.close()
        if let capturedOutput { try? files.removeItem(at: capturedOutput) }
    }
    try process.run()
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw ReleaseError("\(executable) failed with status \(process.terminationStatus)")
    }

    if let capturedOutput {
        return try String(contentsOf: capturedOutput, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return ""
}

func append(_ value: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
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
    let downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case id, name
        case downloadURL = "browser_download_url"
    }
}

struct GitHubRelease: Decodable {
    let id: Int
    let tagName: String
    let isDraft: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case id, assets
        case tagName = "tag_name"
        case isDraft = "draft"
    }
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

    func releasesPage(_ page: Int) async throws -> [GitHubRelease] {
        let data = try await request("repos/\(repository)/releases?per_page=100&page=\(page)")

        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    func releases() async throws -> [GitHubRelease] {
        var page = 1
        var all: [GitHubRelease] = []
        while true {
            let releases = try await releasesPage(page)
            all += releases
            if releases.count < 100 { return all }
            page += 1
        }
    }

    func release(_ version: String) async throws -> GitHubRelease? {
        var page = 1
        while true {
            let releases = try await releasesPage(page)
            if let release = releases.first(where: { $0.tagName == version }) { return release }
            if releases.count < 100 { return nil }
            page += 1
        }
    }

    func send(_ path: String, method: String, value: some Encodable) async throws -> Data {
        try await request(path, method: method, body: JSONEncoder().encode(value))
    }
}

enum ReleaseLabel: String, CaseIterable, Comparable {
    case noRelease = "release:none"
    case patch = "release:patch"
    case minor = "release:minor"
    case major = "release:major"

    static let prefix = "release:"
    static let choices = allCases.reversed().map(\.rawValue).joined(separator: ", ")

    var rank: Int {
        switch self {
        case .noRelease: 0
        case .patch: 1
        case .minor: 2
        case .major: 3
        }
    }

    var bump: VersionBump? {
        switch self {
        case .noRelease: nil
        case .patch: .patch
        case .minor: .minor
        case .major: .major
        }
    }

    static func < (lhs: ReleaseLabel, rhs: ReleaseLabel) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum VersionBump {
    case patch
    case minor
    case major

    var label: ReleaseLabel {
        switch self {
        case .patch: .patch
        case .minor: .minor
        case .major: .major
        }
    }
}

struct ReleaseVersion: Comparable, CustomStringConvertible {
    static let marker = "-agoodkind."
    static let format = "MAJOR.MINOR.PATCH-agoodkind.N"

    let major: Int
    let minor: Int
    let patch: Int
    let build: Int

    var description: String { "\(major).\(minor).\(patch)\(Self.marker)\(build)" }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch, lhs.build) < (rhs.major, rhs.minor, rhs.patch, rhs.build)
    }

    static func parse(_ name: String) throws -> ReleaseVersion? {
        let halves = name.components(separatedBy: marker)
        guard halves.count == 2 else { return nil }

        let fields = halves[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init) + [halves[1]]
        guard fields.count == 4, fields.allSatisfy(isDecimal) else { return nil }

        let numbers = fields.compactMap { Int($0) }
        guard numbers.count == fields.count else {
            throw ReleaseError("Tag or reservation \(name) has a version number above \(Int.max). Keep every published tag unchanged and ask a maintainer to choose the next release version.")
        }
        guard numbers[3] > 0 else { return nil }

        return ReleaseVersion(major: numbers[0], minor: numbers[1], patch: numbers[2], build: numbers[3])
    }

    static func isDecimal(_ field: String) -> Bool {
        guard let first = field.first, field.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }

        return first != "0" || field.count == 1
    }

    func next(_ bump: VersionBump) throws -> ReleaseVersion {
        func increment(_ value: Int, _ component: String) throws -> Int {
            guard value < Int.max else {
                throw ReleaseError("Version \(self) has no room for a \(bump.label.rawValue) release because its \(component) number is \(Int.max). Keep every published tag unchanged and ask a maintainer to choose the next release version.")
            }

            return value + 1
        }
        switch bump {
        case .major: return try ReleaseVersion(major: increment(major, "major"), minor: 0, patch: 0, build: 1)
        case .minor: return try ReleaseVersion(major: major, minor: increment(minor, "minor"), patch: 0, build: 1)
        case .patch: return try ReleaseVersion(major: major, minor: minor, patch: increment(patch, "patch"), build: 1)
        }
    }
}

struct PullRequestLabels: Codable {
    let number: Int
    let labels: [String]

    func releaseLabel() throws -> ReleaseLabel {
        let releaseLabels = labels.filter { $0.hasPrefix(ReleaseLabel.prefix) }
        let unknown = releaseLabels.filter { ReleaseLabel(rawValue: $0) == nil }
        guard unknown.isEmpty else {
            throw ReleaseError("Remove \(unknown.joined(separator: ", ")) from PR #\(number) and keep exactly one of \(ReleaseLabel.choices)")
        }
        guard releaseLabels.count < 2 else {
            throw ReleaseError("Remove all but one of \(releaseLabels.joined(separator: ", ")) from PR #\(number) so it has exactly one of \(ReleaseLabel.choices)")
        }
        guard let name = releaseLabels.first, let label = ReleaseLabel(rawValue: name) else {
            throw ReleaseError("Add exactly one of \(ReleaseLabel.choices) to PR #\(number)")
        }

        return label
    }
}

struct CommitLabels: Codable {
    let sha: String
    let pullRequests: [PullRequestLabels]
}

struct ReleaseInput: Codable {
    let publishedReleases: [String]
    let commits: [CommitLabels]

    static func load() throws -> ReleaseInput {
        let path = try required("RELEASE_INPUT_PATH")
        guard let data = files.contents(atPath: path) else {
            throw ReleaseError("Release input \(path) does not exist. Run the collect-release-input command before prepare.")
        }

        return try JSONDecoder().decode(ReleaseInput.self, from: data)
    }
}

struct AssociatedPullRequest: Decodable {
    struct Label: Decodable { let name: String }

    let number: Int
    let mergedAt: String?
    let labels: [Label]

    enum CodingKeys: String, CodingKey {
        case number, labels
        case mergedAt = "merged_at"
    }
}

enum VersionSource: String {
    case requestedTag = "requested-tag"
    case publishedRelease = "published-release"
    case incompletePublication = "incomplete-publication"
    case reservation
    case newReservation = "new-reservation"
}

enum ReleasePlan {
    case existing(ReleaseVersion, VersionSource)
    case unreleased(predecessor: ReleaseVersion, commits: [String])
}

let reservationNamespace = "refs/release-reservations/"

func git(_ arguments: [String]) throws -> String {
    try run("git", arguments, outputMode: .capture)
}

func verifyReleaseTag(_ version: ReleaseVersion, source: String) throws {
    let reference = "refs/tags/\(version)"
    let commit = try git(["rev-parse", "\(reference)^{commit}"])
    guard commit == source else {
        throw ReleaseError("Tag \(version) does not match source commit \(source)")
    }

    let object = try git(["rev-parse", reference])
    let remote = try git(["ls-remote", "--refs", "origin", reference])
    guard remote == "\(object)\t\(reference)" else {
        throw ReleaseError("Origin tag \(version) does not match the verified local tag")
    }
}

func createReleaseTag(_ version: ReleaseVersion, source: String) throws {
    let reference = "refs/tags/\(version)"
    let tags = try git(["tag", "--list", version.description])
    if tags.isEmpty {
        try run("git", ["tag", version.description, source])
    }

    guard try git(["rev-parse", "\(reference)^{commit}"]) == source else {
        throw ReleaseError("Tag \(version) does not match source commit \(source)")
    }

    if try git(["ls-remote", "--refs", "origin", reference]).isEmpty {
        try run("git", ["push", "origin", reference])
    }
    try verifyReleaseTag(version, source: source)
}

func lines(_ text: String) -> [String] {
    text.split(separator: "\n").map(String.init)
}

func versions(_ names: [String]) throws -> [ReleaseVersion] {
    try names.compactMap { try ReleaseVersion.parse($0) }
}

func fetchReleaseRefs() throws {
    try run("git", ["fetch", "--quiet", "--force", "origin", "+refs/tags/*:refs/tags/*",
                    "+\(reservationNamespace)*:\(reservationNamespace)*"])
}

func releaseTags(_ arguments: [String] = []) throws -> [ReleaseVersion] {
    try versions(lines(git(["tag", "--list"] + arguments)))
}

func reservations(_ arguments: [String] = []) throws -> [ReleaseVersion] {
    try versions(lines(git(["for-each-ref", "--format=%(refname:lstrip=2)"] + arguments + [reservationNamespace])))
}

func isNewestRelease(_ version: ReleaseVersion, published: [String]) throws -> Bool {
    try versions(published).allSatisfy { $0 <= version }
}

let sourcePolicyPath = ".release-source-policy"

func sourceArchiveRequired(at revision: String) throws -> Bool {
    let paths = try lines(git(["ls-tree", "--name-only", revision, "--", sourcePolicyPath]))
    guard !paths.isEmpty else { return false }

    let policy = try git(["show", "\(revision):\(sourcePolicyPath)"])
    guard policy == "1" else {
        throw ReleaseError("Unsupported source archive policy \(policy) at \(revision)")
    }
    return true
}

func completeReleaseTags(_ releases: [GitHubRelease]) throws -> [String] {
    let candidates = try releases.filter { release in
        guard !release.isDraft else { return false }
        return try ReleaseVersion.parse(release.tagName) != nil
    }
    let requirements = try candidates.map { release in
        let sourceArchive = try sourceArchiveRequired(at: release.tagName)
        return (release: release, required: ReleaseContext.assetNames(release.tagName, sourceArchive: sourceArchive))
    }
    return requirements.filter { entry in
        let names = Set(entry.release.assets.map(\.name))
        return entry.required.allSatisfy(names.contains)
    }.map { $0.release.tagName }
}

func releasePlan(head: String, requested: String, published: Set<String>) throws -> ReleasePlan {
    if !requested.isEmpty {
        guard let version = try ReleaseVersion.parse(requested), try !lines(git(["tag", "--list", requested])).isEmpty else {
            throw ReleaseError("REQUESTED_TAG must select an existing \(ReleaseVersion.format) tag")
        }
        guard try git(["rev-parse", "\(requested)^{commit}"]) == head else {
            throw ReleaseError("Requested release tag must identify the checked-out commit")
        }

        return .existing(version, .requestedTag)
    }
    if let tag = try releaseTags(["--points-at", head]).max() {
        return .existing(tag, published.contains(tag.description) ? .publishedRelease : .incompletePublication)
    }
    if let reserved = try reservations(["--points-at", head]).max() {
        return .existing(reserved, .reservation)
    }
    guard let predecessor = try releaseTags(["--merged", head]).filter({ published.contains($0.description) }).max() else {
        throw ReleaseError("Commit \(head) has no ancestor tag with a complete published release. Run the release workflow with the tag of the newest ancestor release to finish its publication.")
    }

    let commits = try lines(git(["rev-list", "--first-parent", "--reverse", "\(predecessor)..\(head)"]))
    return .unreleased(predecessor: predecessor, commits: commits)
}

func highestLabel(commits: [String], head: String, in input: ReleaseInput) throws -> ReleaseLabel {
    var entries: [String: [PullRequestLabels]] = [:]
    for commit in input.commits {
        entries[commit.sha] = commit.pullRequests
    }
    var problems: [String] = []
    var checked = Set<Int>()
    var highest = ReleaseLabel.noRelease
    for sha in commits {
        guard let pullRequests = entries[sha] else {
            problems.append("The release input lacks commit \(sha). Run the collect-release-input command on the same checkout before prepare.")
            continue
        }
        guard !pullRequests.isEmpty else {
            problems.append("Commit \(sha) has no associated merged pull request. Tag commit \(sha) with the release version that matches its change, push the tag, and run the release workflow with that tag.")
            continue
        }

        for pullRequest in pullRequests where checked.insert(pullRequest.number).inserted {
            do {
                highest = try max(highest, pullRequest.releaseLabel())
            } catch {
                problems.append("\(error)")
            }
        }
    }
    guard problems.isEmpty else {
        problems.append("Fix each problem above, then run the release workflow again for commit \(head).")
        throw ReleaseError(problems.joined(separator: "\n"))
    }

    return highest
}

struct ReleaseContext {
    let version: String
    let release: ReleaseVersion
    let root: URL
    let directory: URL
    let github: GitHub

    init(version: String, root: URL, github: GitHub) throws {
        guard let release = try ReleaseVersion.parse(version) else {
            throw ReleaseError("VERSION must match \(ReleaseVersion.format)")
        }

        self.version = version
        self.release = release
        self.root = root
        self.github = github
        directory = root.appendingPathComponent("release", isDirectory: true)
    }

    static func assetNames(_ version: String, sourceArchive: Bool) -> [String] {
        var names = ["periphery-\(version)-macos-arm64.zip", "periphery-\(version)-macos-arm64.dmg", "install.sh"]
        if sourceArchive { names.append("periphery-\(version)-source.tar.gz") }
        return names + ["checksums.txt"]
    }

    var archiveName: String { "periphery-\(version)-macos-arm64.zip" }
    var diskImage: URL { directory.appendingPathComponent("periphery-\(version)-macos-arm64.dmg") }
    var product: URL { directory.appendingPathComponent("periphery-\(version)", isDirectory: true) }
    func assetNames() throws -> [String] {
        try Self.assetNames(version, sourceArchive: sourceArchiveRequired(at: "HEAD"))
    }

    func checkRelease() async throws {
        if let release = try await github.release(version), !release.isDraft {
            let names = Set(release.assets.map(\.name))
            for name in try assetNames() where !names.contains(name) {
                throw ReleaseError("Published release \(version) lacks \(name). Dispatch with an empty tag to create a complete release.")
            }
            try append("exists=true\n", to: URL(fileURLWithPath: required("GITHUB_OUTPUT")))
            print("Reusing published release \(version)")
        } else {
            try append("exists=false\n", to: URL(fileURLWithPath: required("GITHUB_OUTPUT")))
        }
    }

    func build() throws {
        guard try sourceArchiveRequired(at: "HEAD") else {
            try build(at: root)
            return
        }
        let extraction = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: extraction, withIntermediateDirectories: true)
        let source = extraction.appendingPathComponent("periphery-\(version)", isDirectory: true)
        let archive = directory.appendingPathComponent("periphery-\(version)-source.tar.gz")
        let outcome = Result<Void, Error> {
            try run("tar", ["-xzf", archive.path, "-C", extraction.path])
            try build(at: source)
            try verifyBazel(at: source)
        }
        do {
            try files.removeItem(at: extraction)
        } catch {
            if case let .failure(failure) = outcome {
                throw ReleaseError("\(failure); cannot remove source extraction \(extraction.path): \(error)")
            }
            throw ReleaseError("Cannot remove source extraction \(extraction.path): \(error)")
        }
        try outcome.get()
    }

    func build(at source: URL) throws {
        try run(required("SWIFT_COMMAND"), ["build", "-c", "release", "--arch", "arm64", "--product", "periphery", "--scratch-path", ".build/arm64"], at: source)
        try files.createDirectory(at: product, withIntermediateDirectories: true)
        try files.copyItem(at: source.appendingPathComponent(".build/arm64/release/periphery"), to: product.appendingPathComponent("periphery"))
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

    func sourceArchive() throws {
        guard try sourceArchiveRequired(at: "HEAD") else { return }
        let source = try required("SOURCE_SHA")
        guard try git(["rev-parse", "HEAD"]) == source else {
            throw ReleaseError("SOURCE_SHA must equal the checked-out commit")
        }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: temporary) }
        let index = temporary.appendingPathComponent("index").path
        let indexEnvironment = ["GIT_INDEX_FILE": index]
        try run("git", ["read-tree", source], extraEnvironment: indexEnvironment)
        let installerEntry = try git(["ls-tree", source, "--", "scripts/install.sh"])
        guard let installerMode = installerEntry.split(separator: " ").first,
              installerMode == "100644" || installerMode == "100755" else {
            throw ReleaseError("Cannot read the installer file mode from \(source)")
        }
        for (path, mode, pattern, replacement) in [
            ("Sources/Frontend/Version.swift", "100644", #"^let PeripheryVersion = ".*"$"#, "let PeripheryVersion = \"\(version)\""),
            ("scripts/install.sh", String(installerMode), "^VERSION=.*$", "VERSION=\(version)"),
            ("MODULE.bazel", "100644", #"^    version = ".*",$"#, "    version = \"\(version)\","),
        ] {
            let input = temporary.appendingPathComponent(UUID().uuidString)
            try run("git", ["show", "\(source):\(path)"], outputMode: .file(input))
            try replace(pattern, with: replacement, in: input)
            let hash = try run("git", ["hash-object", "-w", input.path], outputMode: .capture)
            try run("git", ["update-index", "--add", "--cacheinfo", "\(mode),\(hash),\(path)"], extraEnvironment: indexEnvironment)
        }
        let tree = try run("git", ["write-tree"], outputMode: .capture, extraEnvironment: indexEnvironment)
        let timestamp = try git(["show", "-s", "--format=%cI", source])
        let archive = directory.appendingPathComponent("periphery-\(version)-source.tar.gz")
        try run("git", ["archive", "--format=tar.gz", "--mtime=\(timestamp)", "--prefix=periphery-\(version)/",
                        "--output=\(archive.path)", tree])
    }

    func verifyBazel(at source: URL) throws {
        let output = source.deletingLastPathComponent().appendingPathComponent("bazel-output")
        let option = "--output_user_root=\(output.path)"
        var problems: [String] = []
        do {
            try run("bazel", [option, "build", "//:periphery"], at: source)
            let binary = source.appendingPathComponent("bazel-bin/Sources/Frontend_opt").path
            guard try run(binary, ["version"], at: source, outputMode: .capture) == version else {
                throw ReleaseError("Bazel source archive executable version must equal \(version)")
            }
        } catch {
            problems.append("\(error)")
        }
        do {
            try run("bazel", [option, "shutdown"], at: source)
        } catch {
            problems.append("Cannot stop the source archive Bazel server: \(error)")
        }
        do {
            if files.fileExists(atPath: output.path) {
                try run("chmod", ["-R", "u+w", output.path])
                try files.removeItem(at: output)
            }
        } catch {
            problems.append("Cannot remove Bazel output \(output.path): \(error)")
        }
        guard problems.isEmpty else { throw ReleaseError(problems.joined(separator: "\n")) }
    }

    func checksums() throws {
        try files.copyItem(at: root.appendingPathComponent("scripts/install.sh"), to: directory.appendingPathComponent("install.sh"))
        let lines = try assetNames().dropLast().map { name in
            try "\(checksum(directory.appendingPathComponent(name)))  \(name)\n"
        }.joined()
        try lines.write(to: directory.appendingPathComponent("checksums.txt"), atomically: true, encoding: .utf8)
    }

    func publish() async throws {
        let source = try required("SOURCE_SHA")
        guard try git(["rev-parse", "HEAD"]) == source else {
            throw ReleaseError("SOURCE_SHA must equal the checked-out commit")
        }
        let names = try assetNames()
        for name in names {
            guard files.fileExists(atPath: directory.appendingPathComponent(name).path) else {
                throw ReleaseError("Release asset \(name) does not exist")
            }
        }
        try verifyReleaseTag(release, source: source)
        let release: GitHubRelease
        if let existing = try await github.release(version) {
            guard existing.isDraft else { throw ReleaseError("Published release assets cannot change") }

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
        for name in names {
            if let asset = release.assets.first(where: { $0.name == name }) {
                _ = try await github.request("repos/\(github.repository)/releases/assets/\(asset.id)", method: "DELETE")
            }
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            _ = try await github.request("repos/\(github.repository)/releases/\(release.id)/assets?name=\(name)", method: "POST", body: data, contentType: "application/octet-stream", host: "uploads.github.com")
        }
        struct Publish: Encodable { let draft = false; let make_latest: String }
        let latest = try isNewestRelease(self.release, published: ReleaseInput.load().publishedReleases) ? "true" : "false"
        _ = try await github.send("repos/\(github.repository)/releases/\(release.id)", method: "PATCH", value: Publish(make_latest: latest))
    }

    func download() async throws {
        guard let release = try await github.release(version), !release.isDraft else {
            throw ReleaseError("Published release \(version) does not exist")
        }

        let names = Set(release.assets.map(\.name))
        for name in try Self.assetNames(version, sourceArchive: sourceArchiveRequired(at: version)) where !names.contains(name) {
            throw ReleaseError("Release \(version) lacks \(name)")
        }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in [archiveName, "checksums.txt"] {
            guard let asset = release.assets.first(where: { $0.name == name }) else {
                throw ReleaseError("Release \(version) lacks \(name)")
            }

            let (temporary, response) = try await URLSession.shared.download(from: asset.downloadURL)
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
        guard try isNewestRelease(release, published: ReleaseInput.load().publishedReleases) else {
            print("Homebrew formula keeps the newer published release because \(version) is older than it")
            return
        }

        let tap = root.appendingPathComponent("homebrew-tap", isDirectory: true)
        let formula = tap.appendingPathComponent("Formula/periphery.rb")
        let digest = try checksum(directory.appendingPathComponent(archiveName))
        let url = "https://github.com/\(github.repository)/releases/download/\(version)/\(archiveName)"
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
    let sourceSHA = try required("SOURCE_SHA", allowEmpty: true)
    let requested = try required("REQUESTED_TAG", allowEmpty: true)
    let head = try run("git", ["rev-parse", "HEAD"], outputMode: .capture)
    guard sourceSHA.isEmpty || sourceSHA == head else { throw ReleaseError("SOURCE_SHA must equal the checked-out commit \(head)") }

    let output = try URL(fileURLWithPath: required("GITHUB_OUTPUT"))
    let version: ReleaseVersion
    let source: VersionSource
    let input = try ReleaseInput.load()
    try fetchReleaseRefs()
    switch try releasePlan(head: head, requested: requested, published: Set(input.publishedReleases)) {
    case let .existing(existing, existingSource):
        version = existing
        source = existingSource
    case let .unreleased(predecessor, commits):
        let label = try highestLabel(commits: commits, head: head, in: input)
        guard let bump = label.bump else {
            print("Every pull request after published release \(predecessor) uses \(ReleaseLabel.noRelease.rawValue). This run does not publish a release.")
            try append("release=false\nsource_sha=\(head)\n", to: output)
            return
        }

        let newest = try (releaseTags() + reservations() + [predecessor]).max() ?? predecessor
        version = try newest.next(bump)
        let reservation = "\(reservationNamespace)\(version)"
        do {
            try run("git", ["push", "--quiet", "--force-with-lease=\(reservation):", "origin", "\(head):\(reservation)"])
        } catch {
            throw ReleaseError("Origin rejected reservation \(reservation) for commit \(head). Run the release workflow again for commit \(head) to allocate the next free version.")
        }
        source = .newReservation
    }
    print("Release version \(version) for commit \(head) comes from \(source.rawValue)")
    let root = URL(fileURLWithPath: files.currentDirectoryPath)
    try replace(#"^let PeripheryVersion = ".*"$"#, with: "let PeripheryVersion = \"\(version)\"", in: root.appendingPathComponent("Sources/Frontend/Version.swift"))
    try replace("^VERSION=.*$", with: "VERSION=\(version)", in: root.appendingPathComponent("scripts/install.sh"))
    try createReleaseTag(version, source: head)
    try append("release=true\nversion=\(version)\nversion_source=\(source.rawValue)\nsource_sha=\(head)\n", to: output)
    try append("VERSION=\(version)\n", to: URL(fileURLWithPath: required("GITHUB_ENV")))
}

func collectReleaseInput() async throws {
    let head = try git(["rev-parse", "HEAD"])
    let destination = try URL(fileURLWithPath: required("RELEASE_INPUT_PATH"))
    let github = try GitHub(repository: required("GITHUB_REPOSITORY"), token: environment["GH_TOKEN"])
    try fetchReleaseRefs()
    let published = try await completeReleaseTags(github.releases())
    var commits: [CommitLabels] = []
    let plan = try releasePlan(head: head, requested: required("REQUESTED_TAG", allowEmpty: true), published: Set(published))
    if case let .unreleased(_, shas) = plan {
        for sha in shas {
            let data = try await github.request("repos/\(github.repository)/commits/\(sha)/pulls")
            let associated = try JSONDecoder().decode([AssociatedPullRequest].self, from: data)
            let merged = associated.filter { $0.mergedAt != nil }
            commits.append(CommitLabels(sha: sha, pullRequests: merged.map {
                PullRequestLabels(number: $0.number, labels: $0.labels.map(\.name))
            }))
        }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(ReleaseInput(publishedReleases: published.sorted(), commits: commits)).write(to: destination, options: .atomic)
    print("Recorded \(published.count) complete published releases and the pull request labels for \(commits.count) unreleased commits in \(destination.path)")
}

func checkPullRequestLabels() throws {
    let number = try required("PULL_REQUEST_NUMBER")
    guard let parsed = Int(number) else { throw ReleaseError("PULL_REQUEST_NUMBER must be a pull request number") }

    let labels = try JSONDecoder().decode([String].self, from: Data(required("PULL_REQUEST_LABELS").utf8))
    let label = try PullRequestLabels(number: parsed, labels: labels).releaseLabel()
    print("PR #\(parsed) uses \(label.rawValue)")
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
    case "collect-release-input": try await collectReleaseInput()
    case "check-pr-labels": try checkPullRequestLabels()
    case "import-certificate": try importCertificate()
    default:
        let github = try GitHub(repository: required("GITHUB_REPOSITORY"), token: environment["GH_TOKEN"])
        let context = try ReleaseContext(version: required("VERSION"),
                                         root: URL(fileURLWithPath: files.currentDirectoryPath, isDirectory: true),
                                         github: github)
        switch command {
        case "check-release": try await context.checkRelease()
        case "build": try context.build()
        case "package": try context.package()
        case "notarize": try context.notarize()
        case "source-archive": try context.sourceArchive()
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
