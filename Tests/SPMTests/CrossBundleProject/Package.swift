// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CrossBundleProject",
    defaultLocalization: "en",
    targets: [
        .executableTarget(name: "App", dependencies: ["Owner", "Lookup"]),
        .target(name: "Owner", resources: [.process("Localizable.xcstrings")]),
        .target(name: "Lookup"),
        .target(name: "Other", resources: [.process("Localizable.xcstrings")]),
    ]
)
