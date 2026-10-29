@testable import Indexer
import SyntaxAnalysis
import XCTest

final class LocalizedStringCallResolverTest: XCTestCase {
    private typealias Parameter = LocalizedStringCallResolver.Parameter
    private typealias Argument = LocalizedStringCallSite.Argument

    func testParsesEmptyParameterList() {
        XCTAssertEqual(LocalizedStringCallResolver.parameters(fromDemangledSignature: "Module.run() -> ()"), [])
    }

    func testRetainsUnmatchedArguments() {
        let parameters = [Parameter(label: "title", type: "Swift.String")]
        let arguments = [Argument(label: "other", keys: ["unmatched"])]

        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: arguments, parameters: parameters), ["unmatched"])
    }
}
