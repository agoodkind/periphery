import Configuration
import Foundation
import Logger
import Shared

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class UpdateChecker {
    private let logger: Logger
    private let debugLogger: ContextualLogger
    private let configuration: Configuration
    private let urlSession: URLSession
    private let latestReleaseURL: URL
    private var latestVersion: String?
    private let semaphore: DispatchSemaphore
    private var error: Error?

    required init(logger: Logger, configuration: Configuration) {
        self.logger = logger
        debugLogger = logger.contextualized(with: "update-check")
        self.configuration = configuration
        let config = URLSessionConfiguration.ephemeral
        urlSession = URLSession(configuration: config)
        latestReleaseURL = URL(string: "https://github.com/agoodkind/periphery/releases/latest")!
        semaphore = DispatchSemaphore(value: 0)
    }

    deinit {
        urlSession.invalidateAndCancel()
    }

    func run() {
        // We only perform the update check with xcode format because it may interfere with
        // parsing json and csv.
        guard !configuration.disableUpdateCheck,
              configuration.outputFormat.supportsAuxiliaryOutput else { return }

        var urlRequest = URLRequest(url: latestReleaseURL)
        urlRequest.httpMethod = "HEAD"

        let task = urlSession.dataTask(with: urlRequest) { [weak self] _, response, error in
            guard let self else { return }

            if let error {
                debugLogger.debug("error: \(error.localizedDescription)")
                self.error = error
                semaphore.signal()
                return
            }

            do {
                latestVersion = try Self.releaseTag(from: response)
            } catch {
                self.error = error
                debugLogger.debug(error.localizedDescription)
            }
            semaphore.signal()
        }

        task.resume()
    }

    private static func releaseTag(from response: URLResponse?) throws -> String {
        guard let response = response as? HTTPURLResponse else {
            throw PeripheryError.updateCheckError(message: "Latest release lookup did not return an HTTP response.")
        }
        guard response.statusCode == 200 else {
            throw PeripheryError.updateCheckError(message: "Latest release lookup returned HTTP \(response.statusCode).")
        }

        let prefix = "/agoodkind/periphery/releases/tag/"
        guard let url = response.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "github.com",
              components.port == nil, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.percentEncodedPath.hasPrefix(prefix)
        else {
            throw PeripheryError.updateCheckError(message: "Latest release lookup did not redirect to a fork release.")
        }

        let encodedTag = String(components.percentEncodedPath.dropFirst(prefix.count))
        guard let tag = encodedTag.removingPercentEncoding, !tag.isEmpty else {
            throw PeripheryError.updateCheckError(message: "Latest release lookup did not identify a valid release tag.")
        }

        return tag
    }

    func notifyIfAvailable() {
        guard let latestVersion else { return }

        debugLogger.debug("latest: \(latestVersion)")

        guard PeripheryVersion != "development" else { return }
        guard latestVersion.isVersion(greaterThan: PeripheryVersion) else { return }

        logger.info(logger.colorize("\nUpdate Available!", .boldGreen))
        let boldLatestVersion = logger.colorize(latestVersion, .bold)
        let boldLocalVersion = logger.colorize(PeripheryVersion, .bold)
        logger.info("Fork release \(boldLatestVersion) is available. The installed version is \(boldLocalVersion).")
        logger.info("Release notes: " + logger.colorize("https://github.com/agoodkind/periphery/releases/tag/\(latestVersion)", .bold))
        let boldOption = logger.colorize("--disable-update-check", .bold)
        let boldScan = logger.colorize("scan", .bold)
        logger.info("To disable update checks pass the \(boldOption) option to the \(boldScan) command.")
    }

    func wait() -> Result<String, PeripheryError> {
        let waitResult = semaphore.wait(timeout: .now() + 60)

        if let error {
            return .failure(.underlyingError(error))
        }

        if waitResult == .timedOut {
            return .failure(PeripheryError.updateCheckError(message: "Timed out while checking for update."))
        }

        if let latestVersion {
            return .success(latestVersion)
        }

        return .failure(PeripheryError.updateCheckError(message: "Failed to determine latest version."))
    }
}
