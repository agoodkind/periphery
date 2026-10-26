import Foundation
import SystemPackage
@testable import TestShared

var UIKitProjectPath: FilePath {
    ProjectRootPath.appending("Tests/XcodeTests/UIKitProject/UIKitProject.xcodeproj")
}

var SwiftUIProjectPath: FilePath {
    ProjectRootPath.appending("Tests/XcodeTests/SwiftUIProject/SwiftUIProject.xcodeproj")
}

var SyncedGroupProjectRoot: FilePath {
    ProjectRootPath.appending("Tests/XcodeTests/SyncedGroupProject")
}

var SyncedGroupProjectPath: FilePath {
    SyncedGroupProjectRoot.appending("SyncedGroupProject.xcodeproj")
}
