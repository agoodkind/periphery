// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CrossBundleProject",
    defaultLocalization: "en",
    targets: [
        .executableTarget(name: "App", dependencies: ["Owner", "Lookup"]),
        .target(name: "Owner", resources: [.copy("Localizable.xcstrings"), .process("Resources")]),
        .target(name: "Lookup"),
        .target(name: "Other", resources: [.process("Localizable.xcstrings")]),
    ]
)
