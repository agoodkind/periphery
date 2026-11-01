//
//  check-bcr.swift
//  Periphery
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-11-01
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct RegistryError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

let environment = ProcessInfo.processInfo.environment
let module = "agoodkind-periphery"
let owner = "agoodkind"
let registry = "bazelbuild/bazel-central-registry"
let fork = "agoodkind/bazel-central-registry"

func required(_ name: String) throws -> String {
    guard let value = environment[name], !value.isEmpty else {
        throw RegistryError("Set \(name) before checking registry publication")
    }

    return value
}

func baseURL(_ name: String, default value: String) throws -> URL {
    guard let url = URL(string: environment[name] ?? value),
          ["https", "http"].contains(url.scheme), url.host != nil else {
        throw RegistryError("Set \(name) to an HTTP or HTTPS URL")
    }

    return url
}

func request(_ url: URL, method: String = "GET", token: String? = nil) async throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: url, timeoutInterval: 30)
    request.httpMethod = method
    if let token {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Periphery-release", forHTTPHeaderField: "User-Agent")
    }
    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await URLSession.shared.data(for: request)
    } catch {
        throw RegistryError("Registry preflight request failed for \(url): \(error.localizedDescription)")
    }
    guard let response = response as? HTTPURLResponse else {
        throw RegistryError("Registry preflight did not receive an HTTP response from \(url)")
    }

    return (data, response)
}

struct PullRequest: Decodable {
    struct User: Decodable { let login: String }
    struct Repository: Decodable { let full_name: String }
    struct Branch: Decodable {
        let ref: String
        let repo: Repository?
    }

    let number: Int
    let state: String
    let title: String
    let user: User
    let head: Branch
    let base: Branch

    func matches(_ version: String) -> Bool {
        state == "open" && user.login == owner && head.repo?.full_name == fork &&
            base.repo?.full_name == registry && base.ref == "main" &&
            (head.ref == "\(module)-\(version)" || title == "\(module)@\(version)")
    }
}

func shouldSkip(_ version: String, token: String) async throws -> Bool {
    let registryURL = try baseURL("BCR_REGISTRY_URL", default: "https://bcr.bazel.build/")
    let source = registryURL.appendingPathComponent("modules/\(module)/\(version)/source.json")
    let (_, response) = try await request(source, method: "HEAD")
    switch response.statusCode {
    case 200:
        print("Registry already publishes \(module)@\(version)")
        return true
    case 404: break
    default:
        throw RegistryError("Registry publication check failed with HTTP \(response.statusCode) for \(source)")
    }

    let api = try baseURL("GITHUB_API_URL", default: "https://api.github.com/")
    var page = 1
    while true {
        let url = api.appendingPathComponent("repos/\(registry)/pulls")
            .appending(queryItems: [URLQueryItem(name: "state", value: "open"),
                                   URLQueryItem(name: "per_page", value: "100"),
                                   URLQueryItem(name: "page", value: String(page))])
        let (data, response) = try await request(url, token: token)
        guard response.statusCode == 200 else {
            throw RegistryError("Registry pull request check failed with HTTP \(response.statusCode) for \(url)")
        }

        let requests: [PullRequest]
        do {
            requests = try JSONDecoder().decode([PullRequest].self, from: data)
        } catch {
            throw RegistryError("Cannot read registry pull requests on page \(page): \(error)")
        }
        if let existing = requests.first(where: { $0.matches(version) }) {
            print("Registry PR #\(existing.number) already proposes \(module)@\(version)")
            return true
        }
        guard requests.count == 100 else { return false }

        page += 1
    }
}

do {
    let version = try required("VERSION")
    guard version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+-agoodkind\.[0-9]+$"#, options: .regularExpression) == version.startIndex ..< version.endIndex else {
        throw RegistryError("Set VERSION to an agoodkind/periphery release version")
    }

    let output = try URL(fileURLWithPath: required("GITHUB_OUTPUT"))
    let skip = try await shouldSkip(version, token: required("GH_TOKEN"))
    let handle = try FileHandle(forWritingTo: output)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("skip=\(skip)\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(EXIT_FAILURE)
}
