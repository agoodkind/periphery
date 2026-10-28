import Foundation

/// Referenced only by the `customClassName` of a Core Data model that SwiftPM processes.
public final class SPMImplicitModelTransformer: ValueTransformer {
    override public func transformedValue(_ value: Any?) -> Any? {
        value
    }
}

public final class SPMDeclaredModelTransformer: ValueTransformer {
    override public func transformedValue(_ value: Any?) -> Any? {
        value
    }
}

/// Not referenced by any model or code.
public final class SPMUnusedModelTransformer: ValueTransformer {
    override public func transformedValue(_ value: Any?) -> Any? {
        value
    }
}
