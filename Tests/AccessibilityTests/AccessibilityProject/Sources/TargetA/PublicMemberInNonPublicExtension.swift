import Foundation

// #45: a public member declared in a non-public extension of a type that is not publicly accessible.

struct PublicMemberInInternalTypeExtension {}

extension PublicMemberInInternalTypeExtension {
    public func publicFuncInInternalTypeExtension() {}
}

private struct PublicMemberInPrivateTypeExtension {}

extension PublicMemberInPrivateTypeExtension {
    public func publicFuncInPrivateTypeExtension() {}
}

fileprivate struct PublicMemberInFileprivateTypeExtension {}

extension PublicMemberInFileprivateTypeExtension {
    public func publicFuncInFileprivateTypeExtension() {}
}

protocol PublicMemberInInternalProtocolExtension {}

extension PublicMemberInInternalProtocolExtension {
    public func publicFuncInInternalProtocolExtension() {}
}

struct PublicMemberInInternalTypeExtension_Outer {
    struct Inner {}
}

extension PublicMemberInInternalTypeExtension_Outer.Inner {
    public func publicFuncInNestedTypeOfInternalTypeExtension() {}
}

public struct PublicMemberInInternalNestedTypeExtension_Outer {
    public init() {}
    struct Inner {}
    public func retainInner() {
        Inner().publicFuncInInternalNestedTypeExtension()
    }
}

extension PublicMemberInInternalNestedTypeExtension_Outer.Inner {
    public func publicFuncInInternalNestedTypeExtension() {}
}

public class PublicMemberInRedundantPublicTypeExtension {}

extension PublicMemberInRedundantPublicTypeExtension {
    public func publicFuncInRedundantPublicTypeExtension() {}
}

// Nested internal type declared directly in a public type that is used cross module.
public class PublicMemberInInternalNestedType_Outer {
    public init() {}
    class Inner {
        public func publicFuncInInternalNestedType() {}
    }

    public func retainInner() {
        Inner().publicFuncInInternalNestedType()
    }
}

// Nested internal type declared in an extension of a public type that is used cross module.
public class PublicMemberInInternalNestedTypeOfExtension_Outer {
    public init() {}
}

extension PublicMemberInInternalNestedTypeOfExtension_Outer {
    struct Inner {
        public func publicFuncInInternalNestedTypeOfExtension() {}
    }

    public func retainExtensionInner() {
        Inner().publicFuncInInternalNestedTypeOfExtension()
    }
}

// Controls: a public type used cross module keeps the public members of its non-public extension.
public class PublicMemberInNonPublicExtensionOfPublicType {
    public init() {}
}

extension PublicMemberInNonPublicExtensionOfPublicType {
    public func publicFuncInNonPublicExtensionOfPublicType() {}
}

public protocol PublicMemberInNonPublicExtensionOfPublicProtocol {}

extension PublicMemberInNonPublicExtensionOfPublicProtocol {
    public func publicFuncInNonPublicExtensionOfPublicProtocol() {}
}

extension PublicMemberInNonPublicExtensionOfPublicType: PublicMemberInNonPublicExtensionOfPublicProtocol {}

extension String {
    public func publicFuncInExternalTypeExtension() {}
}

public class PublicMemberInNonPublicExtensionRetainer {
    public init() {}
    public func retain() {
        PublicMemberInInternalTypeExtension().publicFuncInInternalTypeExtension()
        PublicMemberInPrivateTypeExtension().publicFuncInPrivateTypeExtension()
        PublicMemberInFileprivateTypeExtension().publicFuncInFileprivateTypeExtension()
        PublicMemberInInternalProtocolExtensionImpl().publicFuncInInternalProtocolExtension()
        PublicMemberInInternalTypeExtension_Outer.Inner().publicFuncInNestedTypeOfInternalTypeExtension()
        PublicMemberInRedundantPublicTypeExtension().publicFuncInRedundantPublicTypeExtension()
    }
}

struct PublicMemberInInternalProtocolExtensionImpl: PublicMemberInInternalProtocolExtension {}
