/// The structure records how inactive platform-conditional code refers to one identifier.
/// `receiverNames` contains the receivers before the identifier in member references.
/// `hasUnknownReceiver` is `true` when at least one reference does not state its receiver.
public struct PlatformConditionalNameUse: Equatable {
    public var hasUnknownReceiver = false
    public var receiverNames: Set<String> = []

    public init() {}

    public mutating func merge(_ other: Self) {
        hasUnknownReceiver = hasUnknownReceiver || other.hasUnknownReceiver
        receiverNames.formUnion(other.receiverNames)
    }
}
