@resultBuilder
public struct PublicResultBuilder {
    public static func buildBlock(_ components: String...) -> String {
        components.joined()
    }

    public static func buildExpression(_ expression: String) -> String {
        expression
    }

    public static func buildOptional(_ component: String?) -> String {
        component ?? ""
    }
}

public struct PublicResultBuilderUser {
    public init(@PublicResultBuilder content: () -> String) {
        _ = content()
    }
}
