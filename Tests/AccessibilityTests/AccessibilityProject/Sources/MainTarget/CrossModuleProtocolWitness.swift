import TargetA

final class InternalClassWitnessingCrossModuleProtocol: PublicProtocolWithStaticRequirementUsedByExtension {
    public static var bundleName: String { "a" }
}

func retainCrossModuleProtocolWitnesses() {
    _ = InternalClassWitnessingCrossModuleProtocol.instantiateFromBundle()
}
