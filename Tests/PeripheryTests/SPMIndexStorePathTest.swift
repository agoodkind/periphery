import Configuration
import Foundation
import Logger
@testable import ProjectDrivers
import Shared
import SystemPackage
import XCTest

final class SPMIndexStorePathTest: XCTestCase {
    private final class StubShell: Shell, @unchecked Sendable {
        let output: String
        private(set) var commands: [[String]] = []

        init(output: String) {
            self.output = output
        }

        func exec(_ args: [String]) throws -> String {
            commands.append(args)
            return output
        }

        func execStatus(_: [String]) throws -> Int32 {
            0
        }
    }

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("periphery-spm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func makeDirectory(_ relativePath: String) throws -> FilePath {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return FilePath(url.path)
    }

    private func makePackage(binPath: FilePath, output: String? = nil) -> (SPM.Package, StubShell) {
        let shell = StubShell(output: output ?? "\(binPath)\n")
        let package = SPM.Package(configuration: Configuration(), shell: shell, logger: Logger(quiet: true, verbose: false, colorMode: .never))
        return (package, shell)
    }

    func testSwiftBuildBackendStore() throws {
        let bin = try makeDirectory(".build/out/Products/Debug")
        _ = try makeDirectory(".build/out/v5/units")
        let (package, _) = makePackage(binPath: bin)

        let resolved = try package.indexStorePath(additionalArguments: [])
        XCTAssertEqual(resolved, bin.removingLastComponent().removingLastComponent())
    }

    func testSwiftBuildBackendReleaseStore() throws {
        let bin = try makeDirectory(".build/out/Products/Release")
        _ = try makeDirectory(".build/out/v5/records")
        let (package, _) = makePackage(binPath: bin)

        let resolved = try package.indexStorePath(additionalArguments: ["-c", "release"])
        XCTAssertEqual(resolved, bin.removingLastComponent().removingLastComponent())
    }

    func testNativeBackendStore() throws {
        let bin = try makeDirectory(".build/arm64-apple-macosx/debug")
        _ = try makeDirectory(".build/arm64-apple-macosx/debug/index/store/v5/units")
        let (package, _) = makePackage(binPath: bin)

        let resolved = try package.indexStorePath(additionalArguments: ["--build-system", "native"])
        XCTAssertEqual(resolved, bin.appending("index/store"))
    }

    func testStoreNotFoundThrowsWithTriedPaths() throws {
        let bin = try makeDirectory(".build/out/Products/Debug")
        // A store directory without a 'v5' subdirectory is not a store.
        _ = try makeDirectory(".build/out/Products/Debug/index/store")
        let (package, _) = makePackage(binPath: bin)

        XCTAssertThrowsError(try package.indexStorePath(additionalArguments: [])) { error in
            guard case let PeripheryError.spmIndexStoreNotFound(tried) = error else {
                return XCTFail("Unexpected error: \(error)")
            }

            XCTAssertEqual(tried.count, 2)
            XCTAssertTrue(tried[0].hasSuffix(".build/out/Products/Debug/index/store"))
            XCTAssertTrue(tried[1].hasSuffix(".build/out"))
            XCTAssertTrue(error.localizedDescription.contains("--index-store-path"))
        }
    }

    func testBinPathUsesLastLineOfOutput() throws {
        let bin = try makeDirectory(".build/out/Products/Debug")
        let (package, _) = makePackage(binPath: bin, output: "warning: something\n\(bin)\n\n")

        XCTAssertEqual(try package.binPath(additionalArguments: []), bin)
    }

    func testBinPathEmptyOutputThrows() throws {
        let (package, _) = makePackage(binPath: FilePath("/unused"), output: "\n")
        XCTAssertThrowsError(try package.binPath(additionalArguments: []))
    }

    func testOnlyLocationArgumentsAreForwarded() throws {
        let bin = try makeDirectory(".build/out/Products/Debug")
        let (package, shell) = makePackage(binPath: bin)

        _ = try package.binPath(additionalArguments: [
            "--build-tests", "-v", "-c", "release", "--skip-build",
            "--scratch-path", "/tmp/scratch", "--build-system=native",
            "--triple", "arm64-apple-macosx", "-Xswiftc", "-warnings-as-errors",
            "--toolchain=/tmp/tc", "--configuration",
        ])

        XCTAssertEqual(shell.commands, [[
            "swift", "build", "--show-bin-path",
            "-c", "release",
            "--scratch-path", "/tmp/scratch",
            "--build-system=native",
            "--triple", "arm64-apple-macosx",
            "-Xswiftc", "-warnings-as-errors",
            "--toolchain=/tmp/tc",
        ]])
    }
}
