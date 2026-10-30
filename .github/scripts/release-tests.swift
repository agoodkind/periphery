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

struct CommandResult {
    let status: Int32
    let output: String
}

let files = FileManager.default
let publishedRepository = "agoodkind/periphery"
let reservationNamespace = "refs/release-reservations/"

func execute(_ executable: String, _ arguments: [String], at directory: URL,
             environment overrides: [String: String] = [:]) throws -> CommandResult
{
    let output = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    guard files.createFile(atPath: output.path, contents: nil) else {
        throw RegressionError("Cannot create the command output file")
    }

    let handle = try FileHandle(forWritingTo: output)
    defer {
        try? handle.close()
        try? files.removeItem(at: output)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.currentDirectoryURL = directory
    var environment = ProcessInfo.processInfo.environment
    environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment.merge(overrides) { _, override in override }
    process.environment = environment
    process.standardOutput = handle
    process.standardError = handle
    try process.run()
    process.waitUntilExit()
    let result = try String(contentsOf: output, encoding: .utf8)
    return CommandResult(status: process.terminationReason == .exit ? process.terminationStatus : -1,
                         output: result.trimmingCharacters(in: .whitespacesAndNewlines))
}

@discardableResult
func run(_ executable: String, _ arguments: [String], at directory: URL,
         environment: [String: String] = [:]) throws -> String
{
    let result = try execute(executable, arguments, at: directory, environment: environment)
    guard result.status == 0 else {
        throw RegressionError("\(executable) \(arguments.joined(separator: " ")) failed with status \(result.status):\n\(result.output)")
    }

    return result.output
}

func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    guard condition else { throw RegressionError(message()) }
}

struct PullRequestEntry: Encodable {
    let number: Int
    let labels: [String]
}

struct CommitEntry: Encodable {
    let sha: String
    let pullRequests: [PullRequestEntry]
}

struct ReleaseInputEntry: Encodable {
    let publishedReleases: [String]
    let commits: [CommitEntry]
}

struct Checkout {
    let directory: URL

    @discardableResult
    func git(_ arguments: [String]) throws -> String {
        try run("git", arguments, at: directory)
    }

    func commit(_ message: String) throws -> String {
        try git(["-c", "commit.gpgSign=false", "commit", "--allow-empty", "--quiet", "-m", message])
        try git(["push", "--quiet", "origin", "HEAD:main"])
        return try git(["rev-parse", "HEAD"])
    }

    func tag(_ name: String, at commit: String = "HEAD") throws {
        try git(["tag", name, commit])
        try git(["push", "--quiet", "origin", "refs/tags/\(name)"])
    }

    func remoteRefs(_ pattern: String) throws -> [String: String] {
        var refs: [String: String] = [:]
        for line in try git(["ls-remote", "origin", pattern]).split(separator: "\n") {
            let fields = line.split(separator: "\t").map(String.init)
            refs[fields[1]] = fields[0]
        }
        return refs
    }

    func contents(_ path: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(path), encoding: .utf8)
    }
}

struct PrepareResult {
    let status: Int32
    let output: String
    let values: [String: String]
}

final class Fixture {
    static let initialVersion = "0.0.0-agoodkind.1"

    let release: URL
    let root: URL
    let origin: URL

    init(release: URL) throws {
        self.release = release
        root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        origin = root.appendingPathComponent("origin.git", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        try run("git", ["init", "--quiet", "--bare", "--initial-branch=main", origin.path], at: root)
    }

    deinit {
        try? files.removeItem(at: root)
    }

    func clone(_ name: String) throws -> Checkout {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try run("git", ["clone", "--quiet", origin.path, directory.path], at: root)
        let checkout = Checkout(directory: directory)
        try checkout.git(["config", "user.name", "Periphery release regression"])
        try checkout.git(["config", "user.email", "noreply@agoodkind.io"])
        return checkout
    }

    func seed() throws -> Checkout {
        let checkout = try clone("seed")
        let sources = checkout.directory.appendingPathComponent("Sources/Frontend", isDirectory: true)
        let scripts = checkout.directory.appendingPathComponent("scripts", isDirectory: true)
        try files.createDirectory(at: sources, withIntermediateDirectories: true)
        try files.createDirectory(at: scripts, withIntermediateDirectories: true)
        try "let PeripheryVersion = \"\(Self.initialVersion)\"\n".write(
            to: sources.appendingPathComponent("Version.swift"), atomically: true, encoding: .utf8
        )
        try "#!/usr/bin/env bash\nVERSION=\(Self.initialVersion)\n".write(
            to: scripts.appendingPathComponent("install.sh"), atomically: true, encoding: .utf8
        )
        try checkout.git(["add", "Sources/Frontend/Version.swift", "scripts/install.sh"])
        _ = try checkout.commit("Initialize release fixture")
        return checkout
    }

    func retryCheckout(_ name: String, at commit: String) throws -> Checkout {
        let checkout = try clone(name)
        try checkout.git(["checkout", "--quiet", "--detach", commit])
        return checkout
    }

    func prepare(_ checkout: Checkout, published: [String], labels: [CommitEntry] = []) throws -> PrepareResult {
        let output = root.appendingPathComponent("output-\(UUID().uuidString)")
        let githubEnvironment = root.appendingPathComponent("environment-\(UUID().uuidString)")
        let inputPath = root.appendingPathComponent("release-input-\(UUID().uuidString).json")
        try Data().write(to: output)
        try Data().write(to: githubEnvironment)
        try JSONEncoder().encode(ReleaseInputEntry(publishedReleases: published, commits: labels)).write(to: inputPath)
        let result = try execute(release.path, ["prepare"], at: checkout.directory, environment: [
            "SOURCE_SHA": "",
            "REQUESTED_TAG": "",
            "GITHUB_OUTPUT": output.path,
            "GITHUB_ENV": githubEnvironment.path,
            "RELEASE_INPUT_PATH": inputPath.path,
        ])
        return try PrepareResult(status: result.status, output: result.output, values: outputs(output))
    }

    func checkRelease(_ checkout: Checkout, version: String) throws -> String? {
        let output = root.appendingPathComponent("output-\(UUID().uuidString)")
        try Data().write(to: output)
        try run(release.path, ["check-release"], at: checkout.directory, environment: [
            "VERSION": version,
            "GITHUB_REPOSITORY": publishedRepository,
            "GITHUB_OUTPUT": output.path,
        ])
        return try outputs(output)["exists"]
    }

    func outputs(_ url: URL) throws -> [String: String] {
        var values: [String: String] = [:]
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            guard let separator = line.firstIndex(of: "="), separator != line.startIndex else {
                throw RegressionError("\(url.path) has a line without a key=value pair: \(line)")
            }

            values[String(line[..<separator])] = String(line[line.index(after: separator)...])
        }
        return values
    }
}

func entry(_ sha: String, _ number: Int, _ labels: [String]) -> CommitEntry {
    CommitEntry(sha: sha, pullRequests: [PullRequestEntry(number: number, labels: labels)])
}

func expectAllocation(_ result: PrepareResult, _ checkout: Checkout, version: String, at commit: String) throws {
    try expect(result.status == 0, "prepare failed:\n\(result.output)")
    try expect(result.values["release"] == "true", "prepare must request a release:\n\(result.output)")
    try expect(result.values["version"] == version, "prepare chose \(result.values["version"] ?? "nothing") instead of \(version)")
    try expect(result.values["version_source"] == "new-reservation", "prepare must reserve a new version:\n\(result.output)")
    let reserved = try checkout.remoteRefs("\(reservationNamespace)\(version)")
    try expect(reserved["\(reservationNamespace)\(version)"] == commit, "origin must hold reservation \(version) at \(commit)")
    try expect(checkout.contents("Sources/Frontend/Version.swift").contains("\"\(version)\""), "Version.swift must contain \(version)")
    try expect(checkout.contents("scripts/install.sh").contains("VERSION=\(version)\n"), "install.sh must contain \(version)")
}

func expectRejection(_ result: PrepareResult, _ checkout: Checkout, message: String) throws {
    try expect(result.status != 0, "prepare must fail with \(message)")
    try expect(result.output.contains(message), "prepare must report \(message), received:\n\(result.output)")
    try expect(checkout.remoteRefs("\(reservationNamespace)*").isEmpty, "a rejected range must not reserve a version")
}

func releaseRange(_ release: URL, labelSets: [[String]],
                  verify: (PrepareResult, Checkout, [String]) throws -> Void) throws
{
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    try checkout.tag("3.8.0-agoodkind.7")
    var commits: [String] = []
    var entries: [CommitEntry] = []
    for (index, labels) in labelSets.enumerated() {
        let sha = try checkout.commit("Merge pull request \(100 + index)")
        commits.append(sha)
        entries.append(entry(sha, 100 + index, labels))
    }
    try verify(fixture.prepare(checkout, published: ["3.8.0-agoodkind.7"], labels: entries), checkout, commits)
}

func testAllocation(_ release: URL, labelSets: [[String]], version: String) throws {
    try releaseRange(release, labelSets: labelSets) { result, checkout, commits in
        try expectAllocation(result, checkout, version: version, at: commits.last!)
    }
}

func testNoneOnly(_ release: URL) throws {
    try releaseRange(release, labelSets: [["release:none"], ["documentation", "release:none"]]) { result, checkout, _ in
        try expect(result.status == 0, "prepare failed:\n\(result.output)")
        try expect(result.values["release"] == "false", "a release:none range must not publish:\n\(result.output)")
        try expect(result.values["version"] == nil, "a release:none range must not choose a version")
        try expect(checkout.remoteRefs("\(reservationNamespace)*").isEmpty, "a release:none range must not reserve a version")
        try expect(checkout.contents("Sources/Frontend/Version.swift").contains(Fixture.initialVersion),
                   "a release:none range must not stamp Version.swift")
    }
}

func testRejection(_ release: URL, labels: [String], message: String) throws {
    try releaseRange(release, labelSets: [["release:patch"], labels]) { result, checkout, _ in
        try expectRejection(result, checkout, message: message)
    }
}

func testCommitWithoutPullRequest(_ release: URL) throws {
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    try checkout.tag("3.8.0-agoodkind.7")
    let labeled = try checkout.commit("Merge pull request 100")
    let direct = try checkout.commit("Push directly to the release branch")
    let result = try fixture.prepare(checkout, published: ["3.8.0-agoodkind.7"], labels: [
        entry(labeled, 100, ["release:patch"]), CommitEntry(sha: direct, pullRequests: []),
    ])
    try expectRejection(result, checkout, message: "Commit \(direct) has no associated merged pull request")
}

func testLegacyTags(_ release: URL) throws {
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    try checkout.tag("3.0.0.beta1")
    try checkout.tag("3.8.0")
    var published: [String] = []
    for build in 1 ... 7 {
        _ = try checkout.commit("Release legacy build \(build)")
        try checkout.tag("3.8.0-agoodkind.\(build)")
        published.append("3.8.0-agoodkind.\(build)")
    }
    let fix = try checkout.commit("Merge pull request 100")
    let result = try fixture.prepare(checkout, published: published, labels: [entry(fix, 100, ["release:patch"])])
    try expectAllocation(result, checkout, version: "3.8.1-agoodkind.1", at: fix)
}

func testNumericOrdering(_ release: URL) throws {
    let minorFixture = try Fixture(release: release)
    let minorCheckout = try minorFixture.seed()
    try minorCheckout.tag("3.9.0-agoodkind.1")
    _ = try minorCheckout.commit("Merge pull request 100")
    try minorCheckout.tag("3.10.0-agoodkind.1")
    let minorFix = try minorCheckout.commit("Merge pull request 101")
    let minorResult = try minorFixture.prepare(minorCheckout, published: ["3.9.0-agoodkind.1", "3.10.0-agoodkind.1"],
                                               labels: [entry(minorFix, 101, ["release:patch"])])
    try expectAllocation(minorResult, minorCheckout, version: "3.10.1-agoodkind.1", at: minorFix)

    let buildFixture = try Fixture(release: release)
    let buildCheckout = try buildFixture.seed()
    try buildCheckout.tag("3.8.0-agoodkind.9")
    let feature = try buildCheckout.commit("Merge pull request 100")
    try buildCheckout.tag("3.8.0-agoodkind.10")
    let buildFix = try buildCheckout.commit("Merge pull request 101")
    let buildResult = try buildFixture.prepare(buildCheckout, published: ["3.8.0-agoodkind.9", "3.8.0-agoodkind.10"], labels: [
        entry(feature, 100, ["release:minor"]), entry(buildFix, 101, ["release:patch"]),
    ])
    try expectAllocation(buildResult, buildCheckout, version: "3.8.1-agoodkind.1", at: buildFix)
}

func testOverflow(_ release: URL, tag: String, label: String, component: String) throws {
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    try checkout.tag(tag)
    let change = try checkout.commit("Merge pull request 100")
    let result = try fixture.prepare(checkout, published: [tag], labels: [entry(change, 100, [label])])
    try expectRejection(result, checkout, message: "Version \(tag) has no room for a \(label) release because its \(component) number is \(Int.max)")
}

func testRetryAfterFailedBuild(_ release: URL) throws {
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    try checkout.tag("1.0.0-agoodkind.1")
    let fix = try checkout.commit("Merge pull request 100")
    try expectAllocation(fixture.prepare(checkout, published: ["1.0.0-agoodkind.1"], labels: [entry(fix, 100, ["release:patch"])]),
                         checkout, version: "1.0.1-agoodkind.1", at: fix)

    let retry = try fixture.retryCheckout("retry", at: fix)
    let result = try fixture.prepare(retry, published: ["1.0.0-agoodkind.1"])
    try expect(result.status == 0, "the retry failed:\n\(result.output)")
    try expect(result.values["version"] == "1.0.1-agoodkind.1", "the retry must reuse reservation 1.0.1-agoodkind.1:\n\(result.output)")
    try expect(result.values["version_source"] == "reservation", "the retry must report its reservation:\n\(result.output)")
    try expect(retry.remoteRefs("\(reservationNamespace)*").count == 1, "the retry must not reserve a second version")
    try expect(fixture.checkRelease(retry, version: "1.0.1-agoodkind.1") == "false",
               "check-release must find that \(publishedRepository) has not published 1.0.1-agoodkind.1")
}

func testRetryAfterTaggedUploadFailure(_ release: URL) throws {
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    try checkout.tag("1.0.0-agoodkind.1")
    _ = try checkout.commit("Merge pull request 100")
    try checkout.tag("1.0.1-agoodkind.1")
    let result = try fixture.prepare(checkout, published: ["1.0.0-agoodkind.1"])
    try expect(result.status == 0, "the retry failed:\n\(result.output)")
    try expect(result.values["version"] == "1.0.1-agoodkind.1", "the retry must reuse tag 1.0.1-agoodkind.1:\n\(result.output)")
    try expect(result.values["version_source"] == "incomplete-publication",
               "the retry must report an incomplete publication:\n\(result.output)")
    try expect(fixture.checkRelease(checkout, version: "1.0.1-agoodkind.1") == "false",
               "check-release must find that \(publishedRepository) has not published 1.0.1-agoodkind.1")
}

func testRetryAfterPublishedRelease(_ release: URL) throws {
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    try checkout.tag("3.8.0-agoodkind.7")
    let result = try fixture.prepare(checkout, published: ["3.8.0-agoodkind.7"])
    try expect(result.status == 0, "the retry failed:\n\(result.output)")
    try expect(result.values["release"] == "true", "the retry must continue to check-release:\n\(result.output)")
    try expect(result.values["version"] == "3.8.0-agoodkind.7", "the retry must reuse tag 3.8.0-agoodkind.7:\n\(result.output)")
    try expect(result.values["version_source"] == "published-release", "the retry must report its published release:\n\(result.output)")
    try expect(fixture.checkRelease(checkout, version: "3.8.0-agoodkind.7") == "true",
               "check-release must find the published 3.8.0-agoodkind.7 release in \(publishedRepository)")
}

func testIncompletePublicationPredecessor(_ release: URL, formula: Data) throws {
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    try checkout.tag("3.8.0-agoodkind.7")
    let published = ["3.8.0-agoodkind.7"]
    let commitA = try checkout.commit("Merge pull request 301")
    try expectAllocation(fixture.prepare(checkout, published: published, labels: [entry(commitA, 301, ["release:minor"])]),
                         checkout, version: "3.9.0-agoodkind.1", at: commitA)
    try checkout.tag("3.9.0-agoodkind.1", at: commitA)

    let commitB = try checkout.commit("Merge pull request 302")
    try expectAllocation(fixture.prepare(checkout, published: published, labels: [
        entry(commitA, 301, ["release:minor"]), entry(commitB, 302, ["release:patch"]),
    ]), checkout, version: "3.10.0-agoodkind.1", at: commitB)
    try checkout.tag("3.10.0-agoodkind.1", at: commitB)

    let retry = try fixture.retryCheckout("retry", at: commitA)
    let result = try fixture.prepare(retry, published: published)
    try expect(result.status == 0, "the retry of commit A failed:\n\(result.output)")
    try expect(result.values["version"] == "3.9.0-agoodkind.1", "commit A must finish 3.9.0-agoodkind.1:\n\(result.output)")
    try expect(result.values["version_source"] == "incomplete-publication",
               "commit A must report an incomplete publication:\n\(result.output)")

    let tap = try HomebrewTap(fixture: fixture, formula: formula)
    let digest = try tap.publish(fixture, from: retry, version: "3.9.0-agoodkind.1", published: published)
    try tap.expectFormula(fixture, version: "3.9.0-agoodkind.1", digest: digest)
}

func markedCommit(_ checkout: Checkout) throws -> String {
    try "1\n".write(to: checkout.directory.appendingPathComponent(".release-source-policy"), atomically: true, encoding: .utf8)
    try "module(\n    name = \"periphery\",\n    version = \"3.8.0\",\n)\n".write(to: checkout.directory.appendingPathComponent("MODULE.bazel"), atomically: true, encoding: .utf8)
    try checkout.git(["add", ".release-source-policy", "MODULE.bazel"])
    return try checkout.commit("Merge pull request 401")
}

func testMarkedPredecessor(_ release: URL, complete: Bool) throws {
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    let legacy = "3.8.0-agoodkind.1"
    let marked = "3.9.0-agoodkind.1"
    try checkout.tag(legacy)
    let markedSHA = try markedCommit(checkout)
    try checkout.tag(marked)
    let head = try checkout.commit("Merge pull request 402")
    var published = [legacy]
    var entries = [entry(markedSHA, 401, ["release:minor"]), entry(head, 402, ["release:patch"])]
    var expected = "3.10.0-agoodkind.1"
    if complete {
        published.append(marked)
        entries = [entry(head, 402, ["release:patch"])]
        expected = "3.9.1-agoodkind.1"
    }
    let result = try fixture.prepare(checkout, published: published, labels: entries)
    try expectAllocation(result, checkout, version: expected, at: head)
}

func testMarkedTaggedRetry(_ release: URL) throws {
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    let legacy = "3.8.0-agoodkind.1"
    let marked = "3.9.0-agoodkind.1"
    try checkout.tag(legacy)
    let source = try markedCommit(checkout)
    try checkout.tag(marked)
    let retry = try fixture.retryCheckout("marked-retry", at: source)
    let result = try fixture.prepare(retry, published: [legacy])
    try expect(result.status == 0, "the marked tag retry failed:\n\(result.output)")
    try expect(result.values["version"] == marked, "the marked retry must reuse its existing tag")
    try expect(result.values["version_source"] == "incomplete-publication", "the marked retry must report incomplete publication")
    let variables = ["VERSION": marked, "GITHUB_REPOSITORY": publishedRepository, "SOURCE_SHA": source]
    try run(release.path, ["source-archive"], at: retry.directory, environment: variables)
    let archive = retry.directory.appendingPathComponent("release/periphery-\(marked)-source.tar.gz")
    let initial = try Data(contentsOf: archive)
    try run(release.path, ["source-archive"], at: retry.directory, environment: variables)
    try expect(try Data(contentsOf: archive) == initial, "marked retries must recreate the same source archive")
    try expect(try retry.remoteRefs("refs/tags/\(marked)")["refs/tags/\(marked)"] == source, "retry must preserve the tagged commit")
}

struct HomebrewTap {
    let origin: URL
    let privateKey: String
    let allowedSigners: URL

    init(fixture: Fixture, formula: Data) throws {
        origin = fixture.root.appendingPathComponent("homebrew-tap.git", isDirectory: true)
        try run("git", ["init", "--quiet", "--bare", "--initial-branch=main", origin.path], at: fixture.root)
        let seed = fixture.root.appendingPathComponent("homebrew-tap-seed", isDirectory: true)
        try run("git", ["clone", "--quiet", origin.path, seed.path], at: fixture.root)
        try run("git", ["config", "user.name", "Periphery release regression"], at: seed)
        try run("git", ["config", "user.email", "noreply@agoodkind.io"], at: seed)
        let formulaDirectory = seed.appendingPathComponent("Formula", isDirectory: true)
        try files.createDirectory(at: formulaDirectory, withIntermediateDirectories: true)
        try formula.write(to: formulaDirectory.appendingPathComponent("periphery.rb"))
        try run("git", ["add", "Formula/periphery.rb"], at: seed)
        try run("git", ["-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "Initialize Homebrew formula"], at: seed)
        try run("git", ["push", "--quiet", "origin", "HEAD:main"], at: seed)

        let generatedKey = fixture.root.appendingPathComponent("generated-key")
        try run("ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-f", generatedKey.path], at: fixture.root)
        privateKey = try String(contentsOf: generatedKey, encoding: .utf8).trimmingCharacters(in: .newlines)
        let publicKey = try String(contentsOf: generatedKey.appendingPathExtension("pub"), encoding: .utf8)
        allowedSigners = fixture.root.appendingPathComponent("allowed-signers")
        try ("noreply@agoodkind.io " + publicKey).write(to: allowedSigners, atomically: true, encoding: .utf8)
    }

    func publish(_ fixture: Fixture, from checkout: Checkout, version: String, published: [String]) throws -> String {
        let inputPath = fixture.root.appendingPathComponent("release-input-\(UUID().uuidString).json")
        try JSONEncoder().encode(ReleaseInputEntry(publishedReleases: published, commits: [])).write(to: inputPath)
        let tap = checkout.directory.appendingPathComponent("homebrew-tap", isDirectory: true)
        try? files.removeItem(at: tap)
        try run("git", ["clone", "--quiet", origin.path, tap.path], at: checkout.directory)
        let releaseDirectory = checkout.directory.appendingPathComponent("release", isDirectory: true)
        try files.createDirectory(at: releaseDirectory, withIntermediateDirectories: true)
        let archive = releaseDirectory.appendingPathComponent("periphery-\(version)-macos-arm64.zip")
        try run("zip", ["-q", archive.path, "periphery.rb"], at: tap.appendingPathComponent("Formula"))
        try run(fixture.release.path, ["homebrew"], at: checkout.directory, environment: [
            "VERSION": version,
            "GITHUB_REPOSITORY": publishedRepository,
            "HOMEBREW_TAP_DEPLOY_KEY": privateKey,
            "RELEASE_INPUT_PATH": inputPath.path,
            "SIGNING_KEY_PATH": fixture.root.appendingPathComponent("release-signing-key-\(UUID().uuidString)").path,
        ])
        return try SHA256.hash(data: Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
    }

    func formula(_ fixture: Fixture) throws -> String {
        try run("git", ["--git-dir", origin.path, "show", "refs/heads/main:Formula/periphery.rb"], at: fixture.root)
    }

    func head(_ fixture: Fixture) throws -> String {
        try run("git", ["--git-dir", origin.path, "rev-parse", "refs/heads/main"], at: fixture.root)
    }

    func expectFormula(_ fixture: Fixture, version: String, digest: String) throws {
        let pushed = try formula(fixture)
        let archiveName = "periphery-\(version)-macos-arm64.zip"
        let downloadURL = "https://github.com/\(publishedRepository)/releases/download/\(version)/\(archiveName)"
        try expect(pushed.contains("\n  version \"\(version)\"\n"), "The pushed Homebrew formula must use version \(version)")
        try expect(pushed.contains("\n  url \"\(downloadURL)\"\n"), "The pushed Homebrew formula must download \(archiveName)")
        try expect(pushed.contains("\n  sha256 \"\(digest)\"\n"), "The pushed Homebrew formula must contain the archive checksum")
        try run("git", ["--git-dir", origin.path, "-c", "gpg.format=ssh", "-c", "gpg.ssh.allowedSignersFile=\(allowedSigners.path)",
                        "verify-commit", "refs/heads/main"], at: fixture.root)
    }
}

func testHomebrewSigning(_ release: URL, formula: Data) throws {
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    try checkout.tag("3.8.0-agoodkind.4")
    let tap = try HomebrewTap(fixture: fixture, formula: formula)
    let digest = try tap.publish(fixture, from: checkout, version: "3.8.0-agoodkind.4", published: ["3.8.0-agoodkind.3"])
    try tap.expectFormula(fixture, version: "3.8.0-agoodkind.4", digest: digest)
}

func testOlderReservationRetry(_ release: URL, formula: Data) throws {
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    let base = try checkout.git(["rev-parse", "HEAD"])
    try checkout.tag("3.8.0-agoodkind.7")
    let tap = try HomebrewTap(fixture: fixture, formula: formula)

    let commitA = try checkout.commit("Merge pull request 201")
    try expectAllocation(fixture.prepare(checkout, published: ["3.8.0-agoodkind.7"], labels: [entry(commitA, 201, ["release:patch"])]),
                         checkout, version: "3.8.1-agoodkind.1", at: commitA)

    let commitB = try checkout.commit("Merge pull request 202")
    try expectAllocation(fixture.prepare(checkout, published: ["3.8.0-agoodkind.7"], labels: [
        entry(commitA, 201, ["release:patch"]), entry(commitB, 202, ["release:patch"]),
    ]), checkout, version: "3.8.2-agoodkind.1", at: commitB)
    try checkout.tag("3.8.2-agoodkind.1", at: commitB)
    let digestB = try tap.publish(fixture, from: checkout, version: "3.8.2-agoodkind.1", published: ["3.8.0-agoodkind.7"])
    try tap.expectFormula(fixture, version: "3.8.2-agoodkind.1", digest: digestB)
    let tapHead = try tap.head(fixture)

    let retry = try fixture.retryCheckout("retry", at: commitA)
    let result = try fixture.prepare(retry, published: ["3.8.0-agoodkind.7", "3.8.2-agoodkind.1"])
    try expect(result.status == 0, "the retry of commit A failed:\n\(result.output)")
    try expect(result.values["version"] == "3.8.1-agoodkind.1", "commit A must keep reservation 3.8.1-agoodkind.1:\n\(result.output)")
    try expect(result.values["version_source"] == "reservation", "commit A must report its reservation:\n\(result.output)")
    try retry.tag("3.8.1-agoodkind.1", at: commitA)
    _ = try tap.publish(fixture, from: retry, version: "3.8.1-agoodkind.1", published: ["3.8.0-agoodkind.7", "3.8.2-agoodkind.1"])
    try expect(tap.head(fixture) == tapHead, "homebrew must not commit a formula for the older 3.8.1-agoodkind.1")
    try tap.expectFormula(fixture, version: "3.8.2-agoodkind.1", digest: digestB)

    let tags = try checkout.remoteRefs("refs/tags/*")
    try expect(tags["refs/tags/3.8.0-agoodkind.7"] == base, "tag 3.8.0-agoodkind.7 must stay at \(base)")
    try expect(tags["refs/tags/3.8.1-agoodkind.1"] == commitA, "tag 3.8.1-agoodkind.1 must identify commit A")
    try expect(tags["refs/tags/3.8.2-agoodkind.1"] == commitB, "tag 3.8.2-agoodkind.1 must stay at commit B")

    let commitC = try checkout.commit("Merge pull request 203")
    try expectAllocation(fixture.prepare(checkout, published: ["3.8.0-agoodkind.7", "3.8.1-agoodkind.1", "3.8.2-agoodkind.1"],
                                         labels: [entry(commitC, 203, ["release:patch"])]),
                         checkout, version: "3.8.3-agoodkind.1", at: commitC)
}

func testPullRequestLabelCheck(_ release: URL) throws {
    let directory = files.temporaryDirectory
    let cases: [(labels: String, status: Bool, message: String)] = [
        (#"["bug","release:patch"]"#, true, "PR #12 uses release:patch"),
        (#"["bug"]"#, false, "Add exactly one of release:major, release:minor, release:patch, release:none to PR #12"),
        (#"["release:patch","release:minor"]"#, false, "Remove all but one of release:patch, release:minor from PR #12"),
        (#"["release:huge"]"#, false, "Remove release:huge from PR #12"),
    ]
    for item in cases {
        let result = try execute(release.path, ["check-pr-labels"], at: directory, environment: [
            "PULL_REQUEST_NUMBER": "12",
            "PULL_REQUEST_LABELS": item.labels,
        ])
        try expect((result.status == 0) == item.status, "check-pr-labels with \(item.labels) returned \(result.status):\n\(result.output)")
        try expect(result.output.contains(item.message), "check-pr-labels with \(item.labels) must report \(item.message), received:\n\(result.output)")
    }
}

func testSourceArchive(_ release: URL) throws {
    let fixture = try Fixture(release: release)
    let checkout = try fixture.seed()
    let version = "3.8.1-agoodkind.1"
    let legacy = try checkout.git(["rev-parse", "HEAD"])
    let variables = ["VERSION": version, "GITHUB_REPOSITORY": publishedRepository, "SOURCE_SHA": legacy]
    try run(release.path, ["source-archive"], at: checkout.directory, environment: variables)
    try expect(!files.fileExists(atPath: checkout.directory.appendingPathComponent("release").path), "Legacy sources must not create a source archive")

    try "1\n".write(to: checkout.directory.appendingPathComponent(".release-source-policy"), atomically: true, encoding: .utf8)
    try "module(\n    name = \"periphery\",\n    version = \"3.8.0\",\n)\n".write(to: checkout.directory.appendingPathComponent("MODULE.bazel"), atomically: true, encoding: .utf8)
    try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: checkout.directory.appendingPathComponent("scripts/install.sh").path)
    let workflows = checkout.directory.appendingPathComponent(".github", isDirectory: true)
    try files.createDirectory(at: workflows, withIntermediateDirectories: true)
    try "workflow\n".write(to: workflows.appendingPathComponent("tool"), atomically: true, encoding: .utf8)
    try checkout.git(["add", ".release-source-policy", "MODULE.bazel", "scripts/install.sh", ".github"])
    let source = try checkout.commit("Add source archive policy")
    try files.createDirectory(at: checkout.directory.appendingPathComponent("workflow-tools"), withIntermediateDirectories: true)
    try "untracked\n".write(to: checkout.directory.appendingPathComponent("workflow-tools/tool"), atomically: true, encoding: .utf8)
    let markedVariables = ["VERSION": version, "GITHUB_REPOSITORY": publishedRepository, "SOURCE_SHA": source]
    let releaseDirectory = checkout.directory.appendingPathComponent("release", isDirectory: true)
    try files.createDirectory(at: releaseDirectory, withIntermediateDirectories: true)
    for name in ["periphery-\(version)-macos-arm64.zip", "periphery-\(version)-macos-arm64.dmg", "install.sh", "checksums.txt"] {
        try Data(name.utf8).write(to: releaseDirectory.appendingPathComponent(name))
    }
    let missing = try execute(release.path, ["publish"], at: checkout.directory, environment: markedVariables)
    try expect(missing.status != 0 && missing.output.contains("Release asset periphery-\(version)-source.tar.gz does not exist"), "Publication must reject a missing source archive")
    try expect(try checkout.remoteRefs("refs/tags/\(version)").isEmpty, "Publication must reject missing assets before pushing a tag")
    let temporary = fixture.root.appendingPathComponent("build-temporary", isDirectory: true)
    try files.createDirectory(at: temporary, withIntermediateDirectories: true)
    var buildVariables = markedVariables
    buildVariables["TMPDIR"] = temporary.path + "/"
    buildVariables["SWIFT_COMMAND"] = "swift"
    let failedBuild = try execute(release.path, ["build"], at: checkout.directory, environment: buildVariables)
    try expect(failedBuild.status != 0 && failedBuild.output.contains("tar failed"), "Build must report a missing source archive")
    try expect(try files.contentsOfDirectory(atPath: temporary.path).isEmpty, "Build must remove its extraction after a failed archive extraction")
    try files.removeItem(at: releaseDirectory.appendingPathComponent("install.sh"))
    try run(release.path, ["source-archive"], at: checkout.directory, environment: markedVariables)
    let archive = checkout.directory.appendingPathComponent("release/periphery-\(version)-source.tar.gz")
    let first = try Data(contentsOf: archive)
    try run(release.path, ["source-archive"], at: checkout.directory, environment: markedVariables)
    try expect(try Data(contentsOf: archive) == first, "Source archive retries must produce identical bytes")
    let extraction = fixture.root.appendingPathComponent("extraction", isDirectory: true)
    try files.createDirectory(at: extraction, withIntermediateDirectories: true)
    try run("tar", ["-xzf", archive.path, "-C", extraction.path], at: fixture.root)
    let extracted = Checkout(directory: extraction.appendingPathComponent("periphery-\(version)"))
    try expect(try extracted.contents("Sources/Frontend/Version.swift").contains("\"\(version)\""), "Source archive must stamp Version.swift")
    try expect(try extracted.contents("scripts/install.sh").contains("VERSION=\(version)"), "Source archive must stamp install.sh")
    try expect(try extracted.contents("MODULE.bazel").contains("name = \"periphery\""), "Source archive must preserve the module name")
    try expect(try extracted.contents("MODULE.bazel").contains("version = \"\(version)\""), "Source archive must stamp MODULE.bazel")
    try expect(files.isExecutableFile(atPath: extracted.directory.appendingPathComponent("scripts/install.sh").path), "Source archive must preserve executable permissions")
    try expect(try extracted.contents(".github/tool") == "workflow\n", "Source archive must preserve tracked GitHub files")
    try expect(!files.fileExists(atPath: extracted.directory.appendingPathComponent("workflow-tools").path), "Source archive must exclude untracked workflow tools")
    for name in ["periphery-\(version)-macos-arm64.zip", "periphery-\(version)-macos-arm64.dmg"] {
        try Data(name.utf8).write(to: checkout.directory.appendingPathComponent("release/\(name)"))
    }
    try run(release.path, ["checksums"], at: checkout.directory, environment: markedVariables)
    let digest = SHA256.hash(data: first).map { String(format: "%02x", $0) }.joined()
    try expect(try checkout.contents("release/checksums.txt").contains("\(digest)  periphery-\(version)-source.tar.gz"), "Checksums must include the source archive")

    try "2\n".write(to: checkout.directory.appendingPathComponent(".release-source-policy"), atomically: true, encoding: .utf8)
    try checkout.git(["add", ".release-source-policy"])
    let unsupported = try checkout.commit("Change source archive policy")
    let rejected = try execute(release.path, ["source-archive"], at: checkout.directory, environment: ["VERSION": version, "GITHUB_REPOSITORY": publishedRepository, "SOURCE_SHA": unsupported])
    try expect(rejected.status != 0 && rejected.output.contains("Unsupported source archive policy 2"), "Unsupported policies must fail clearly")
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw RegressionError("Usage: swift release-tests.swift RELEASE_SCRIPT FORMULA_PATH")
    }

    let releaseScript = URL(fileURLWithPath: CommandLine.arguments[1])
    let formula = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    let workspace = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try files.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: workspace) }
    let release = workspace.appendingPathComponent("release")
    try run("swiftc", [releaseScript.path, "-o", release.path], at: workspace)

    let tests: [(String, () throws -> Void)] = [
        ("patch release", { try testAllocation(release, labelSets: [["bug", "release:patch"]], version: "3.8.1-agoodkind.1") }),
        ("minor release", { try testAllocation(release, labelSets: [["release:minor"]], version: "3.9.0-agoodkind.1") }),
        ("major release", { try testAllocation(release, labelSets: [["release:major"]], version: "4.0.0-agoodkind.1") }),
        ("highest label wins", {
            try testAllocation(release, labelSets: [["release:none"], ["release:patch"], ["release:minor"], ["release:patch"]],
                               version: "3.9.0-agoodkind.1")
        }),
        ("release:none with one release:patch", {
            try testAllocation(release, labelSets: [["release:none"], ["release:patch"], ["release:none"]], version: "3.8.1-agoodkind.1")
        }),
        ("several release:patch pull requests", {
            try testAllocation(release, labelSets: [["release:patch"], ["release:patch"], ["release:patch"]], version: "3.8.1-agoodkind.1")
        }),
        ("release:none only", { try testNoneOnly(release) }),
        ("missing release label", {
            try testRejection(release, labels: ["bug"],
                              message: "Add exactly one of release:major, release:minor, release:patch, release:none to PR #101")
        }),
        ("two release labels", {
            try testRejection(release, labels: ["release:patch", "release:minor"],
                              message: "Remove all but one of release:patch, release:minor from PR #101")
        }),
        ("unknown release label", {
            try testRejection(release, labels: ["release:huge"], message: "Remove release:huge from PR #101")
        }),
        ("commit without pull request", { try testCommitWithoutPullRequest(release) }),
        ("legacy tags", { try testLegacyTags(release) }),
        ("numeric ordering", { try testNumericOrdering(release) }),
        ("major overflow", {
            try testOverflow(release, tag: "\(Int.max).0.0-agoodkind.1", label: "release:major", component: "major")
        }),
        ("patch overflow", {
            try testOverflow(release, tag: "3.8.\(Int.max)-agoodkind.1", label: "release:patch", component: "patch")
        }),
        ("retry after failed build", { try testRetryAfterFailedBuild(release) }),
        ("retry after tagged upload failure", { try testRetryAfterTaggedUploadFailure(release) }),
        ("retry after published release", { try testRetryAfterPublishedRelease(release) }),
        ("incomplete publication is not a predecessor", { try testIncompletePublicationPredecessor(release, formula: formula) }),
        ("incomplete marked tag is not a predecessor", { try testMarkedPredecessor(release, complete: false) }),
        ("complete marked tag is a predecessor", { try testMarkedPredecessor(release, complete: true) }),
        ("marked tagged retry", { try testMarkedTaggedRetry(release) }),
        ("older reservation retry", { try testOlderReservationRetry(release, formula: formula) }),
        ("pull request label check", { try testPullRequestLabelCheck(release) }),
        ("Homebrew signed publication", { try testHomebrewSigning(release, formula: formula) }),
        ("source archive", { try testSourceArchive(release) }),
    ]
    var failures: [String] = []
    for (name, test) in tests {
        do {
            try test()
            print("PASS \(name)")
        } catch {
            failures.append(name)
            print("FAIL \(name): \(error)")
        }
    }
    guard failures.isEmpty else {
        throw RegressionError("\(failures.count) of \(tests.count) release tests failed: \(failures.joined(separator: ", "))")
    }

    print("All \(tests.count) release tests passed")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(EXIT_FAILURE)
}
