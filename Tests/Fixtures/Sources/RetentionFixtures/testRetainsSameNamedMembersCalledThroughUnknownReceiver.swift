import Foundation

public protocol FixtureProtocol234 {}

public struct FixtureStruct234: FixtureProtocol234 {
    func method() {}
}

public struct FixtureStruct235: FixtureProtocol234 {
    func method() {}
}

public class FixtureClass234 {
    private func uniqueUnusedFunction() {}

    public func entry(value: FixtureStruct234) {
        #if os(iOS)
        value.method()
        #endif
    }
}
