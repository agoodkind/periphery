import Foundation
import Logger
import ProjectDrivers
import Shared
import SystemPackage

final class BazelProjectSetupGuide: SetupGuideHelpers, SetupGuide {
    static func detect(logger: Logger) -> Self? {
        guard BazelProjectDriver.isSupported else { return nil }

        return Self(logger: logger)
    }

    var projectKindName: String {
        "Bazel"
    }

    func perform() throws -> ProjectKind {
        let tag: String
        if PeripheryVersion == "development" {
            print("Find a published tag at https://github.com/agoodkind/periphery/releases")
            print("Enter a published fork release tag: ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
                throw PeripheryError.usageError("A published fork release tag is required.")
            }
            tag = input
        } else {
            tag = PeripheryVersion
        }

        let escapedTag = tag.unicodeScalars.map { scalar in
            switch scalar.value {
            case 34: return "\\\""
            case 92: return "\\\\"
            case 0...31, 127: return String(format: "\\x%02x", scalar.value)
            default: return String(scalar)
            }
        }.joined()
        print(logger.colorize("\nAdd the following snippet to your MODULE.bazel file:", .bold))
        print(logger.colorize("""
        bazel_dep(name = "periphery", version = "3.8.0")
        git_override(
            module_name = "periphery",
            remote = "https://github.com/agoodkind/periphery.git",
            tag = "\(escapedTag)",
        )
        use_repo(use_extension("@periphery//bazel:generated.bzl", "generated"), "periphery_generated")
        """, .lightGray))
        print(logger.colorize("\nEnter to continue when ready ", .bold), terminator: "")
        _ = readLine()

        return .bazel
    }

    var commandLineOptions: [String] {
        ["--bazel"]
    }
}
