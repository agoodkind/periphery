public protocol PublicTypeUsedInPublicGenericTypealias_Strategy {
    associatedtype DefaultValue
    static var defaultValue: DefaultValue { get }
}

public struct PublicTypeUsedInPublicGenericTypealias_Wrapper<Strategy: PublicTypeUsedInPublicGenericTypealias_Strategy> {
    public init() {}
}

public struct PublicTypeUsedInPublicGenericTypealias<Value: Sendable>: PublicTypeUsedInPublicGenericTypealias_Strategy {
    public static var defaultValue: Value? { .none }
}

public typealias PublicTypeUsedInPublicGenericTypealias_Alias<Value: Sendable> = PublicTypeUsedInPublicGenericTypealias_Wrapper<PublicTypeUsedInPublicGenericTypealias<Value>>

// Control: an internal typealias does not expose the type.
public struct RedundantPublicTypeUsedInInternalTypealias {}

typealias RedundantPublicTypeUsedInInternalTypealias_Alias = PublicTypeUsedInPublicGenericTypealias_Wrapper<PublicTypeUsedInPublicGenericTypealias<RedundantPublicTypeUsedInInternalTypealias?>>

public class RedundantPublicTypeUsedInInternalTypealiasRetainer {
    public init() {}
    public func retain() {
        _ = RedundantPublicTypeUsedInInternalTypealias_Alias()
    }
}
