import Foundation

@propertyWrapper
public struct FixtureEnvironment227<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

public struct FixtureStruct227 {
    @FixtureEnvironment227 private var sizeClass = 1
    @FixtureEnvironment227 private var unusedSizeClass = 2

    public func entry() {
        #if !os(macOS)
        _ = sizeClass
        #endif
    }
}
