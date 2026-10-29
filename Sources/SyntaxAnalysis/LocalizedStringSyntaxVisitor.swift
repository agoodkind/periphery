import Foundation
import Shared
import SwiftSyntax

/// Collects string keys used for localization in Swift source files.
///
/// Keys are collected in two ways:
/// - `usedStringKeys` holds keys that are known to be used from syntax alone:
///   - `NSLocalizedString("key", ...)`, `String(localized: "key", ...)`, `LocalizedStringKey("key")`,
///     `LocalizedStringResource("key", ...)`, `Text("key")` and `Bundle.localizedString(forKey: "key", ...)`.
///   - Literals assigned to, returned from, or used as the default value of a declaration whose type is a
///     localized type (e.g. `let title: LocalizedStringResource = "key"`).
///   - Literals passed to a call whose callee cannot be located syntactically (conservatively retained).
/// - `callSites` holds the remaining calls that receive string literals. Whether those literals are keys depends on
///   the type of the receiving parameter, which is resolved from the index store by the indexer.
public final class LocalizedStringSyntaxVisitor: PeripherySyntaxVisitor {
    /// Type names whose values are created from a localization key when initialized from a string literal.
    public static let localizedTypeNames = [
        "LocalizedStringKey",
        "LocalizedStringResource",
        "LocalizationValue",
        "DisplayRepresentation",
        "IntentDescription",
    ]

    public private(set) var usedStringKeys: Set<String> = []
    public private(set) var callSites: [LocalizedStringCallSite] = []
    /// The property stores text segments from interpolated string literals that the file passes as call arguments or
    /// uses to initialize declarations with a localized type.
    /// `LocalizedStringRetainer` matches a catalog key when format specifiers join those segments to form the key.
    public private(set) var keyFormatSegments: Set<[String]> = []
    /// The property stores function calls in the file that build localization keys from runtime values.
    /// The syntax tree cannot resolve these calls to catalog keys.
    public private(set) var unresolvedKeys: [LocalizedStringUnresolvedKey] = []

    private let sourceLocationBuilder: SourceLocationBuilder

    public init(sourceLocationBuilder: SourceLocationBuilder, swiftVersion _: SwiftVersion) {
        self.sourceLocationBuilder = sourceLocationBuilder
    }

    public static func isLocalizedType(_ typeName: String) -> Bool {
        localizedTypeNames.contains { typeName.contains($0) }
    }

    public func visit(_ node: FunctionCallExprSyntax) {
        collectKnownCallKeys(node)
        collectCallSite(node)
        collectUnresolvedKey(node)

        for argument in node.arguments {
            collectKeyFormat(argument.expression)
        }
    }

    public func visit(_ node: VariableDeclSyntax) {
        for binding in node.bindings {
            guard let type = binding.typeAnnotation?.type, Self.isLocalizedType(type.trimmedDescription) else { continue }

            if let value = binding.initializer?.value {
                usedStringKeys.formUnion(literalKeys(in: value))
                collectKeyFormat(value)
            }

            if let accessorBlock = binding.accessorBlock {
                usedStringKeys.formUnion(ReturnedLiteralCollector.collect(in: accessorBlock))
            }
        }
    }

    public func visit(_ node: FunctionDeclSyntax) {
        collectDefaultValueKeys(node.signature.parameterClause)

        if let returnType = node.signature.returnClause?.type,
           Self.isLocalizedType(returnType.trimmedDescription),
           let body = node.body
        {
            usedStringKeys.formUnion(ReturnedLiteralCollector.collect(in: body))
        }
    }

    public func visit(_ node: InitializerDeclSyntax) {
        collectDefaultValueKeys(node.signature.parameterClause)
    }

    public func visit(_ node: SubscriptDeclSyntax) {
        collectDefaultValueKeys(node.parameterClause)

        if Self.isLocalizedType(node.returnClause.type.trimmedDescription), let accessorBlock = node.accessorBlock {
            usedStringKeys.formUnion(ReturnedLiteralCollector.collect(in: accessorBlock))
        }
    }

    // MARK: - Private

    private func collectKeyFormat(_ expression: ExprSyntax) {
        if let stringLiteral = expression.as(StringLiteralExprSyntax.self) {
            if let segments = Self.interpolatedTextSegments(of: stringLiteral) {
                keyFormatSegments.insert(segments)
            }
        } else if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1, let element = tuple.elements.first {
            collectKeyFormat(element.expression)
        } else if let ternary = expression.as(TernaryExprSyntax.self) {
            collectKeyFormat(ternary.thenExpression)
            collectKeyFormat(ternary.elseExpression)
        } else if let sequence = expression.as(SequenceExprSyntax.self) {
            for element in sequence.elements {
                collectKeyFormat(element)
            }
        } else if let unresolvedTernary = expression.as(UnresolvedTernaryExprSyntax.self) {
            collectKeyFormat(unresolvedTernary.thenExpression)
        }
    }

    /// The function returns the literal text before, between, and after a string literal's interpolations.
    /// It returns `nil` when the literal does not contain an interpolation.
    private static func interpolatedTextSegments(of stringLiteral: StringLiteralExprSyntax) -> [String]? {
        var segments: [String] = []
        var currentText = ""
        var hasInterpolation = false

        for segment in stringLiteral.segments {
            if let textSegment = segment.as(StringSegmentSyntax.self) {
                currentText += textSegment.content.text
            } else {
                hasInterpolation = true
                segments.append(currentText)
                currentText = ""
            }
        }

        guard hasInterpolation else { return nil }

        segments.append(currentText)
        return segments
    }

    private func collectUnresolvedKey(_ node: FunctionCallExprSyntax) {
        guard let keyExpression = unresolvableKeyExpression(in: node) else { return }

        let location = sourceLocationBuilder.location(at: node.positionAfterSkippingLeadingTrivia)
        unresolvedKeys.append(
            LocalizedStringUnresolvedKey(prefix: literalPrefix(of: keyExpression), line: location.line, column: location.column)
        )
    }

    /// The function returns the key argument of `NSLocalizedString(_:)`, `LocalizedStringKey(_:)`,
    /// `LocalizedStringResource(_:)`, `String.LocalizationValue(_:)`, or `localizedString(forKey:)` when it cannot
    /// resolve that argument.
    /// The format key initializers `LocalizedStringKey`, `LocalizedStringResource`, and `String.LocalizationValue`
    /// accept static and interpolated string literals as resolvable.
    /// `NSLocalizedString` and `localizedString(forKey:)` accept only static string literals as resolvable because they
    /// receive a runtime `String`.
    private func unresolvableKeyExpression(in node: FunctionCallExprSyntax) -> ExprSyntax? {
        let calledExpression = node.calledExpression
        let keyExpression: ExprSyntax
        let acceptsKeyFormat: Bool

        if let identifier = calledExpression.as(DeclReferenceExprSyntax.self),
           ["NSLocalizedString", "LocalizedStringKey", "LocalizedStringResource"].contains(identifier.baseName.text),
           let firstArgument = node.arguments.first,
           firstArgument.label == nil
        {
            keyExpression = firstArgument.expression
            acceptsKeyFormat = identifier.baseName.text != "NSLocalizedString"
        } else if let memberAccess = calledExpression.as(MemberAccessExprSyntax.self),
                  memberAccess.declName.baseName.text == "LocalizationValue",
                  let firstArgument = node.arguments.first,
                  firstArgument.label == nil
        {
            keyExpression = firstArgument.expression
            acceptsKeyFormat = true
        } else if let memberAccess = calledExpression.as(MemberAccessExprSyntax.self),
                  memberAccess.declName.baseName.text == "localizedString",
                  let forKeyArgument = node.arguments.first(where: { $0.label?.text == "forKey" })
        {
            keyExpression = forKeyArgument.expression
            acceptsKeyFormat = false
        } else {
            return nil
        }

        if let stringLiteral = keyExpression.as(StringLiteralExprSyntax.self) {
            let isInterpolated = Self.interpolatedTextSegments(of: stringLiteral) != nil
            return isInterpolated && !acceptsKeyFormat ? keyExpression : nil
        }

        return literalKeys(in: keyExpression).isEmpty ? keyExpression : nil
    }

    /// The function returns the text before a string literal's first interpolation or the left string literal of a
    /// `+` concatenation.
    /// It returns an empty string for every other expression.
    private func literalPrefix(of expression: ExprSyntax) -> String {
        if let stringLiteral = expression.as(StringLiteralExprSyntax.self) {
            return Self.interpolatedTextSegments(of: stringLiteral)?.first ?? stringLiteral.representedLiteralValue ?? ""
        }

        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)

            if elements.count >= 3,
               let binaryOperator = elements[1].as(BinaryOperatorExprSyntax.self),
               binaryOperator.operator.text == "+"
            {
                return literalPrefix(of: elements[0])
            }
        }

        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let binaryOperator = infix.operator.as(BinaryOperatorExprSyntax.self),
           binaryOperator.operator.text == "+"
        {
            return literalPrefix(of: infix.leftOperand)
        }

        return ""
    }

    private func collectDefaultValueKeys(_ clause: FunctionParameterClauseSyntax) {
        for parameter in clause.parameters {
            guard Self.isLocalizedType(parameter.type.trimmedDescription),
                  let value = parameter.defaultValue?.value
            else { continue }

            usedStringKeys.formUnion(literalKeys(in: value))
        }
    }

    private func collectCallSite(_ node: FunctionCallExprSyntax) {
        let arguments = node.arguments.map { argument in
            LocalizedStringCallSite.Argument(label: argument.label?.text, keys: literalKeys(in: argument.expression))
        }

        guard arguments.contains(where: { !$0.keys.isEmpty }) else { return }
        guard let calleeToken = calleeNameToken(of: node.calledExpression) else {
            // The callee cannot be resolved, conservatively assume the literals are keys.
            usedStringKeys.formUnion(arguments.flatMap(\.keys))
            return
        }

        let location = sourceLocationBuilder.location(at: calleeToken.positionAfterSkippingLeadingTrivia)
        callSites.append(LocalizedStringCallSite(line: location.line, column: location.column, arguments: arguments))
    }

    private func calleeNameToken(of expression: ExprSyntax) -> TokenSyntax? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName
        }

        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName
        }

        if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
            return calleeNameToken(of: specialization.expression)
        }

        return nil
    }

    /// Detects well-known localization APIs by name. These are retained regardless of index store resolution.
    private func collectKnownCallKeys(_ node: FunctionCallExprSyntax) {
        let calledExpression = node.calledExpression

        if let identifier = calledExpression.as(DeclReferenceExprSyntax.self) {
            switch identifier.baseName.text {
            case "NSLocalizedString", "LocalizedStringKey", "LocalizedStringResource", "Text":
                // The first unlabeled string argument is the key.
                if let firstArg = node.arguments.first, firstArg.label == nil {
                    insertLiteral(firstArg.expression)
                }
            case "String":
                if let localizedArg = node.arguments.first(where: { $0.label?.text == "localized" }) {
                    insertLiteral(localizedArg.expression)
                }
            default:
                break
            }
            return
        }

        // Handle member access like Bundle.main.localizedString(forKey: "key", ...)
        if let memberAccess = calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "localizedString",
           let forKeyArg = node.arguments.first(where: { $0.label?.text == "forKey" })
        {
            insertLiteral(forKeyArg.expression)
        }
    }

    private func insertLiteral(_ expression: ExprSyntax) {
        if let stringLiteral = expression.as(StringLiteralExprSyntax.self),
           let key = stringLiteral.representedLiteralValue
        {
            usedStringKeys.insert(key)
        }
    }

    /// Static string literals that an expression may evaluate to, looking through parentheses, ternaries and
    /// array literals. String interpolations are ignored since they can't be matched to static keys.
    private func literalKeys(in expression: ExprSyntax) -> [String] {
        if let stringLiteral = expression.as(StringLiteralExprSyntax.self) {
            return stringLiteral.representedLiteralValue.map { [$0] } ?? []
        }

        if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1, let element = tuple.elements.first {
            return literalKeys(in: element.expression)
        }

        if let ternary = expression.as(TernaryExprSyntax.self) {
            return literalKeys(in: ternary.thenExpression) + literalKeys(in: ternary.elseExpression)
        }

        if let unresolvedTernary = expression.as(UnresolvedTernaryExprSyntax.self) {
            return literalKeys(in: unresolvedTernary.thenExpression)
        }

        if let sequence = expression.as(SequenceExprSyntax.self), sequence.elements.contains(where: { $0.is(UnresolvedTernaryExprSyntax.self) }) {
            // An unfolded ternary: `condition ? "a" : "b"`. Only the branches can be keys.
            let elements = Array(sequence.elements)
            guard let ternaryIndex = elements.firstIndex(where: { $0.is(UnresolvedTernaryExprSyntax.self) }) else { return [] }

            return elements[ternaryIndex...].flatMap { literalKeys(in: $0) }
        }

        if let array = expression.as(ArrayExprSyntax.self) {
            return array.elements.flatMap { literalKeys(in: $0.expression) }
        }

        return []
    }
}

/// Collects the string literals a body may return, ignoring literals passed to calls, used in conditions or patterns,
/// or nested in closures and local declarations.
private final class ReturnedLiteralCollector: SyntaxVisitor {
    private var keys: Set<String> = []

    static func collect(in node: some SyntaxProtocol) -> Set<String> {
        let collector = ReturnedLiteralCollector(viewMode: .sourceAccurate)
        collector.walk(node)
        return collector.keys
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        if let key = node.representedLiteralValue {
            keys.insert(key)
        }
        return .skipChildren
    }

    override func visit(_: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: ConditionElementListSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: SwitchCaseLabelSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}
