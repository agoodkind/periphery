import ArgumentParser
import Configuration
import Foundation
import Logger

struct CheckUpdateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check-update",
        abstract: "Check for available update"
    )

    func run() throws {
        let configuration = Configuration()
        let logger = Logger(configuration: configuration)
        let checker = UpdateChecker(logger: logger, configuration: configuration)
        DispatchQueue.global().async { checker.run() }
        let latestRelease = try checker.wait().get()
        let latestVersion = latestRelease.tag
        if PeripheryVersion == "development" {
            logger.info("This development build does not have a release version. The latest fork release is \(latestVersion).")
        } else if latestVersion.isVersion(greaterThan: PeripheryVersion) {
            logger.info(logger.colorize("* Update Available", .boldGreen))
            let boldLatestVersion = logger.colorize(latestVersion, .bold)
            let boldLocalVersion = logger.colorize(PeripheryVersion, .bold)
            logger.info("Version \(boldLatestVersion) is available. The installed version is \(boldLocalVersion).")
        } else if latestVersion.isVersion(equalTo: PeripheryVersion) {
            logger.info("The installed version matches the latest fork release, \(latestVersion).")
        } else {
            logger.info("The installed version is \(PeripheryVersion). The latest fork release is \(latestVersion).")
        }
        logger.info("Release notes: \(latestRelease.url.absoluteString)")
    }
}
