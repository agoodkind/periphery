public protocol PublicClassUsedAsExtensionSameTypeGenericRequirement_Protocol {}

public class PublicClassUsedAsExtensionSameTypeGenericRequirement: PublicClassUsedAsExtensionSameTypeGenericRequirement_Protocol {
    public init() {}
}

extension PublicClassUsedAsExtensionSameTypeGenericRequirement_Protocol where Self == PublicClassUsedAsExtensionSameTypeGenericRequirement {
    public static var defaultClassInstance: Self {
        PublicClassUsedAsExtensionSameTypeGenericRequirement()
    }
}

public extension PublicClassUsedAsExtensionSameTypeGenericRequirement_Protocol where Self == PublicClassUsedAsPublicExtensionSameTypeGenericRequirement {
    static var defaultPublicExtensionInstance: Self {
        PublicClassUsedAsPublicExtensionSameTypeGenericRequirement()
    }
}

public final class PublicClassUsedAsPublicExtensionSameTypeGenericRequirement: PublicClassUsedAsExtensionSameTypeGenericRequirement_Protocol {
    public init() {}
}

public func takeClassExtensionSameTypeGenericRequirement<T: PublicClassUsedAsExtensionSameTypeGenericRequirement_Protocol>(_ value: T) {
    _ = value
}

// Control: the extension has no public member, so the constraining type's public accessibility is redundant.
public protocol RedundantPublicClassUsedAsExtensionSameTypeGenericRequirement_Protocol {}

public class RedundantPublicClassUsedAsExtensionSameTypeGenericRequirement: RedundantPublicClassUsedAsExtensionSameTypeGenericRequirement_Protocol {}

extension RedundantPublicClassUsedAsExtensionSameTypeGenericRequirement_Protocol where Self == RedundantPublicClassUsedAsExtensionSameTypeGenericRequirement {
    static var internalInstance: Self {
        RedundantPublicClassUsedAsExtensionSameTypeGenericRequirement()
    }
}

public class RedundantPublicClassUsedAsExtensionSameTypeGenericRequirementRetainer {
    public init() {}
    public func retain() {
        _ = RedundantPublicClassUsedAsExtensionSameTypeGenericRequirement.internalInstance
    }
}

public struct PublicTypeUsedAsGenericStructExtensionWhereClause_Container<Element> {
    public init() {}
}

public final class PublicTypeUsedAsGenericStructExtensionWhereClause {}

extension PublicTypeUsedAsGenericStructExtensionWhereClause_Container where Element == PublicTypeUsedAsGenericStructExtensionWhereClause {
    public func elementCount() -> Int { 0 }
}

public final class PublicTypeUsedAsPublicFunctionWhereClause {}

public func takePublicFunctionWhereClause<T>(_ value: [T]) where T == PublicTypeUsedAsPublicFunctionWhereClause {
    _ = value
}
