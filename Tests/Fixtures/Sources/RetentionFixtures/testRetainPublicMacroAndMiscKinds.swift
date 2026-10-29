import Foundation

@freestanding(expression)
public macro FixtureRetainPublicMacro() -> String = #externalMacro(module: "FixtureMacroPlugin", type: "FixtureMacro")

@freestanding(expression)
macro FixtureInternalMacro() -> String = #externalMacro(module: "FixtureMacroPlugin", type: "FixtureMacro")

public protocol FixtureRetainPublicProtocol {
    associatedtype FixtureRetainPublicAssoc
}
