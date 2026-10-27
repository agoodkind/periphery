import Configuration
import Foundation
import ProjectDrivers
import SystemPackage

class SPMSourceGraphTestCase: SourceGraphTestCase {
    static func build(projectPath: FilePath = ProjectRootPath, configuration: Configuration = .init()) {
        let hasBuildSystem = configuration.buildArguments.contains {
            $0 == "--build-system" || $0.hasPrefix("--build-system=")
        }
        if !hasBuildSystem {
            configuration.buildArguments += ["--build-system", "native"]
        }

        projectPath.chdir {
            let driver = try! SPMProjectDriver(configuration: configuration, shell: shell, logger: logger)
            try! driver.build()
            plan = try! driver.plan(logger: logger.contextualized(with: "index"))
        }
    }
}
