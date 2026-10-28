import TargetA

RedundantPublicTypeRetainer().retain()
PublicDeclarationInInternalParentRetainer().retain()
PublicExtensionOnRedundantPublicKindRetainer().retain()
IgnoreCommentCommandRetainer().retain()
IgnoreAllCommentCommandRetainer().retain()

_ = PublicTypeUsedAsPublicInitializerParameterTypeRetainer()

_ = PublicTypeUsedAsPublicSubscriptParameterTypeRetainer()[]
_ = PublicTypeUsedAsPublicSubscriptReturnTypeRetainer()[]

PublicTypeUsedAsPublicFunctionParameterTypeRetainer().retain1()
PublicTypeUsedAsPublicFunctionParameterTypeRetainer().retain2()
PublicTypeUsedAsPublicFunctionParameterTypeRetainer().retain3()

PublicTypeUsedAsPublicFunctionParameterDefaultValueRetainer().somePublicFunc()

_ = PublicTypeUsedAsPublicFunctionReturnTypeRetainer().retain1()
_ = PublicTypeUsedAsPublicFunctionReturnTypeRetainer().retain2()
_ = PublicTypeUsedAsPublicFunctionReturnTypeRetainer().retain3()

PublicTypeUsedInPublicFunctionBodyRetainer().retain()
PublicTypeUsedAsPublicFunctionGenericParameterRetainer().retain(PublicTypeUsedAsPublicFunctionGenericParameter_ConformingClass.self)
PublicTypeUsedAsPublicFunctionGenericRequirementRetainer().retain(PublicTypeUsedAsPublicFunctionGenericRequirement_ConformingClass.self)
_ = PublicTypeUsedAsPublicClassGenericParameterRetainer<PublicTypeUsedAsPublicClassGenericParameter_ConformingClass>()
_ = PublicTypeUsedAsPublicClassGenericRequirementRetainer<PublicTypeUsedAsPublicClassGenericRequirement_ConformingClass>()

_ = PublicTypeUsedAsPublicFunctionMetatypeParameterWithGenericReturnTypeRetainer().retain

_ = NotRedundantPublicTestableImportClass().testableProperty

ProtocolIndirectlyReferencedCrossModuleByExtensionMemberImpl().somePublicFunc()

// Properties
_ = PublicTypeUsedAsPublicPropertyTypeRetainer().retain
_ = PublicTypeUsedAsPublicPropertyInitializer().retain

// Result builder
_ = PublicResultBuilderUser {
    "a"
    "b"
}

// Typealias
let _: PublicTypealiasWithClosureType? = nil

// Enum
switch PublicEnumWithAssociatedValue.getSomeCase() {
case let .someCase(a, b):
    _ = a.value
    _ = b.value
}
_ = PublicEnumCaseWithParameter.someCase(param1: nil, param2: nil)

// Inheritance
_ = PublicClassInheritingPublicClass()
_ = PublicClassInheritingPublicExternalClassRetainer()
_ = PublicClassInheritingPublicClassWithGenericParameter()

// Conformance
_ = PublicClassAdoptingPublicProtocol()
_ = PublicClassAdoptingInternalProtocol()
_ = InternalClassAdoptingPublicProtocolRetainer()

// Refining
let _: PublicProtocolRefiningPublicProtocol? = nil
_ = InternalProtocolRefiningPublicProtocolRetainer()

// Closure
let _ = PublicTypeUsedInPublicClosureRetainer().closure

// Async
Task {
    await PublicActor().someFunc()
}

// Property wrappers
_ = PublicWrappedProperty().wrappedProperty

// Inlining
inlinableFunction()

// Associated types
_ = PublicInheritedAssociatedTypeClass().items
_ = PublicInheritedAssociatedTypeDefaultTypeClass().items

// Extension with same-type generic requirement
takeExtensionSameTypeGenericRequirement(.defaultInstance)

// Typed throws
try? PublicTypeUsedAsPublicFunctionThrowTypeRetainer().retain()

// Extension with same-type generic requirement on a class
takeClassExtensionSameTypeGenericRequirement(.defaultClassInstance)
takeClassExtensionSameTypeGenericRequirement(.defaultPublicExtensionInstance)
RedundantPublicClassUsedAsExtensionSameTypeGenericRequirementRetainer().retain()

// Generic typealias
let _: PublicTypeUsedInPublicGenericTypealias_Alias<Int>? = nil
RedundantPublicTypeUsedInInternalTypealiasRetainer().retain()

// Cross-module protocol witness
retainCrossModuleProtocolWitnesses()
_ = PublicTypeUsedAsGenericStructExtensionWhereClause_Container().elementCount()
takePublicFunctionWhereClause([])
