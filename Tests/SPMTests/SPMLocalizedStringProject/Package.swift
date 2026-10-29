// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SPMLocalizedStringProject",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LocalizedStringApp",
            dependencies: ["InterpolationKeys", "DynamicKeys", "PlainKeys", "PrefixKeys", "OwnerA", "OwnerB"]
        ),
        .target(
            name: "InterpolationKeys",
            resources: [.process("Localizable.xcstrings")]
        ),
        .target(
            name: "DynamicKeys",
            resources: [.process("Localizable.xcstrings")]
        ),
        .target(
            name: "PlainKeys",
            resources: [.process("Localizable.xcstrings"), .process("Empty.xcstrings")]
        ),
        .target(
            name: "PrefixKeys",
            resources: [.process("Localizable.xcstrings")]
        ),
        .target(
            name: "OwnerA",
            path: "Modules",
            exclude: ["Shared/OwnerB"],
            sources: ["OwnerA"],
            resources: [.process("Shared/Localizable.xcstrings")]
        ),
        .target(
            name: "OwnerB",
            path: "Modules/Shared/OwnerB"
        ),
    ]
)
