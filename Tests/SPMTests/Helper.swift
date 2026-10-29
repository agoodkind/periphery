import Foundation
import SystemPackage
@testable import TestShared

var SPMProjectPath: FilePath {
    ProjectRootPath.appending("Tests/SPMTests/SPMProject")
}

#if os(macOS)
    var SPMProjectMacOSPath: FilePath {
        ProjectRootPath.appending("Tests/SPMTests/SPMProjectMacOS")
    }

    var SPMLocalizedStringProjectPath: FilePath {
        ProjectRootPath.appending("Tests/SPMTests/SPMLocalizedStringProject")
    }
#endif
