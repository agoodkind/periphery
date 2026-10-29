@testable import Indexer
import SyntaxAnalysis
import XCTest

final class LocalizedStringCallResolverTest: XCTestCase {
    private typealias Parameter = LocalizedStringCallResolver.Parameter
    private typealias Argument = LocalizedStringCallSite.Argument

    func testDemanglesSwiftUSR() {
        let demangled = LocalizedStringCallResolver.demangle(
            usr: "s:7SwiftUI6ButtonVA2A4TextVRszrlE_6actionACyAEGAA18LocalizedStringKeyV_yyctcfc"
        )

        XCTAssertEqual(
            demangled,
            "(extension in SwiftUI):SwiftUI.Button< where A == SwiftUI.Text>.init(_: SwiftUI.LocalizedStringKey, action: () -> ()) -> SwiftUI.Button<SwiftUI.Text>"
        )
    }

    func testDoesNotDemangleNonSwiftUSR() {
        XCTAssertNil(LocalizedStringCallResolver.demangle(usr: "c:objc(cs)NSAlert(im)addButtonWithTitle:"))
    }

    func testParsesLabeledParameters() {
        let parameters = LocalizedStringCallResolver.parameters(
            fromDemangledSignature: "(extension in SwiftUI):SwiftUI.Label< where A == SwiftUI.Text, B == SwiftUI.Image>.init(_: SwiftUI.LocalizedStringKey, systemImage: Swift.String) -> SwiftUI.Label<SwiftUI.Text, SwiftUI.Image>"
        )

        XCTAssertEqual(parameters, [
            Parameter(label: nil, type: "SwiftUI.LocalizedStringKey"),
            Parameter(label: "systemImage", type: "Swift.String"),
        ])
    }

    func testParsesUnlabeledParameters() {
        let parameters = LocalizedStringCallResolver.parameters(
            fromDemangledSignature: "(extension in SwiftUI):SwiftUI.View.navigationTitle(SwiftUI.LocalizedStringKey) -> some"
        )

        XCTAssertEqual(parameters, [Parameter(label: nil, type: "SwiftUI.LocalizedStringKey")])
    }

    func testParsesFunctionTypeParameters() {
        let parameters = LocalizedStringCallResolver.parameters(
            fromDemangledSignature: "Module.run<A where A: Swift.StringProtocol>(_: A, completion: (Swift.Int, Swift.String) -> (), title: [Swift.String: Foundation.LocalizedStringResource]) -> ()"
        )

        XCTAssertEqual(parameters, [
            Parameter(label: nil, type: "A"),
            Parameter(label: "completion", type: "(Swift.Int, Swift.String) -> ()"),
            Parameter(label: "title", type: "[Swift.String: Foundation.LocalizedStringResource]"),
        ])
    }

    func testSkipsPrivateDiscriminator() {
        let parameters = LocalizedStringCallResolver.parameters(
            fromDemangledSignature: "Module.Controller.(showAlert in _81AE913598B2E23132B3415B5C7CAFDE)(title: SwiftUI.LocalizedStringKey) -> ()"
        )

        XCTAssertEqual(parameters, [Parameter(label: "title", type: "SwiftUI.LocalizedStringKey")])
    }

    func testParsesEmptyParameterList() {
        XCTAssertEqual(LocalizedStringCallResolver.parameters(fromDemangledSignature: "Module.run() -> ()"), [])
    }

    func testMatchesArgumentsToParametersSkippingDefaults() {
        let parameters = [
            Parameter(label: nil, type: "SwiftUI.LocalizedStringKey"),
            Parameter(label: "tableName", type: "Swift.Optional<Swift.String>"),
            Parameter(label: "comment", type: "Swift.Optional<Swift.StaticString>"),
        ]
        let arguments = [
            Argument(label: nil, keys: ["key"]),
            Argument(label: "comment", keys: ["comment"]),
        ]

        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: arguments, parameters: parameters), ["key"])
    }

    func testMatchesVariadicArguments() {
        let parameters = [Parameter(label: nil, type: "Foundation.LocalizedStringResource...")]
        let arguments = [Argument(label: nil, keys: ["a"]), Argument(label: nil, keys: ["b"])]

        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: arguments, parameters: parameters), ["a", "b"])
    }

    func testRetainsUnmatchedArguments() {
        let parameters = [Parameter(label: "title", type: "Swift.String")]
        let arguments = [Argument(label: "other", keys: ["unmatched"])]

        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: arguments, parameters: parameters), ["unmatched"])
    }

    func testRetainsKeysOfUnresolvedCallee() {
        let callSite = LocalizedStringCallSite(line: 1, column: 1, arguments: [Argument(label: nil, keys: ["key"])])

        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: callSite, calleeUsrs: []), ["key"])
        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: callSite, calleeUsrs: ["c:objc(cs)NSAlert(im)addButtonWithTitle:"]), ["key"])
    }
}
