//
//  ShellTest.swift
//  Periphery
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-10-25.
//

import Foundation
import Logger
import Shared
import XCTest

final class ShellTest: XCTestCase {
    func testCapturesLargeOutputFromBothStreams() throws {
        let shell = ShellImpl(logger: Logger(quiet: true, verbose: false, colorMode: .never))
        let output = try shell.exec(command(status: 0))
        XCTAssertEqual(output, "stdout:\(String(repeating: "x", count: 262_144)):end")
    }

    func testPreservesBothStreamsOnFailure() throws {
        let shell = ShellImpl(logger: Logger(quiet: true, verbose: false, colorMode: .never))
        let command = command(status: 7)

        XCTAssertThrowsError(try shell.exec(command)) { error in
            guard case let PeripheryError.shellCommandFailed(cmd, status, output) = error else {
                return XCTFail("Expected a shell command failure, received \(error)")
            }

            XCTAssertEqual(cmd, command)
            XCTAssertEqual(status, 7)
            let payload = String(repeating: "x", count: 262_144)
            XCTAssertEqual(output, "stdout:\(payload):end\nstderr:\(payload):end")
        }
    }

    private func command(status: Int) -> [String] {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ShellOutput.sh")
        return ["/bin/bash", "'\(fixture.path)'", String(status)]
    }
}
