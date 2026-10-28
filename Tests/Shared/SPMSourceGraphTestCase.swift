import Configuration
import Foundation
import ProjectDrivers
import SystemPackage

class SPMSourceGraphTestCase: SourceGraphTestCase {
    static func nativeBuildConfiguration() -> Configuration {
        let configuration = Configuration()
        configuration.buildArguments = ["--build-system", "native"]
        return configuration
    }

    static func build(projectPath: FilePath = ProjectRootPath, configuration: Configuration) {
        projectPath.chdir {
            let driver = try! SPMProjectDriver(configuration: configuration, shell: shell, logger: logger)
            try! driver.build()
            plan = try! driver.plan(logger: logger.contextualized(with: "index"))
        }
    }
}
