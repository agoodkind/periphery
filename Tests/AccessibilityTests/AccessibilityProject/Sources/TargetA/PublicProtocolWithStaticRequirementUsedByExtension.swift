public protocol PublicProtocolWithStaticRequirementUsedByExtension {
    static var bundleName: String { get }
}

extension PublicProtocolWithStaticRequirementUsedByExtension {
    public static func instantiateFromBundle() -> String {
        bundleName
    }
}
