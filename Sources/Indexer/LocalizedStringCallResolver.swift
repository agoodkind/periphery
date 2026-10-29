import Foundation
import SyntaxAnalysis

@_silgen_name("swift_demangle")
private func swiftDemangle(
    _: UnsafePointer<CChar>?,
    _: Int,
    _: UnsafeMutablePointer<CChar>?,
    _: UnsafeMutablePointer<Int>?,
    _: UInt32
) -> UnsafeMutablePointer<CChar>?

/// Determines which string literals passed to a call are localization keys, from the parameter types of the called
/// function. The callee is identified by the USRs the index store records at the callee name token; its parameter
/// labels and types are recovered by demangling the USR.
///
/// The resolution is conservative: when the callee or the receiving parameter cannot be determined, the literal is
/// assumed to be a key.
enum LocalizedStringCallResolver {
    struct Parameter: Equatable {
        let label: String?
        let type: String

        var isVariadic: Bool {
            type.hasSuffix("...")
        }
    }

    static func usedKeys(for callSite: LocalizedStringCallSite, calleeUsrs: Set<String>) -> Set<String> {
        guard !calleeUsrs.isEmpty else { return callSite.allKeys }

        var keys: Set<String> = []

        for usr in calleeUsrs {
            guard let demangled = demangle(usr: usr),
                  let parameters = parameters(fromDemangledSignature: demangled)
            else { return callSite.allKeys }

            keys.formUnion(usedKeys(for: callSite.arguments, parameters: parameters))
        }

        return keys
    }

    static func usedKeys(for arguments: [LocalizedStringCallSite.Argument], parameters: [Parameter]) -> Set<String> {
        var keys: Set<String> = []
        var nextIndex = 0
        var lastMatched: Parameter?

        for argument in arguments {
            let parameter: Parameter?

            if argument.label == nil, let lastMatched, lastMatched.isVariadic {
                parameter = lastMatched
            } else if let index = parameters[nextIndex...].firstIndex(where: { $0.label == argument.label }) {
                parameter = parameters[index]
                nextIndex = index + 1
            } else {
                parameter = nil
            }

            guard let parameter else {
                // The argument could not be matched to a parameter, assume the literals are keys.
                keys.formUnion(argument.keys)
                continue
            }

            lastMatched = parameter

            if LocalizedStringSyntaxVisitor.isLocalizedType(parameter.type) {
                keys.formUnion(argument.keys)
            }
        }

        return keys
    }

    static func demangle(usr: String) -> String? {
        guard usr.hasPrefix("s:") else { return nil }

        let mangled = "$s" + usr.dropFirst(2)
        return mangled.withCString { pointer -> String? in
            guard let result = swiftDemangle(pointer, strlen(pointer), nil, nil, 0) else { return nil }

            defer { free(result) }
            return String(cString: result)
        }
    }

    /// Parses the parameter list of a demangled function signature, e.g.
    /// `(extension in SwiftUI):SwiftUI.Button< where A == SwiftUI.Text>.init(_: SwiftUI.LocalizedStringKey, action: () -> ()) -> SwiftUI.Button<SwiftUI.Text>`.
    static func parameters(fromDemangledSignature signature: String) -> [Parameter]? {
        let characters = Array(signature)
        guard let open = parameterListStart(in: characters),
              let close = matchingClose(in: characters, from: open)
        else { return nil }

        let list = String(characters[(open + 1) ..< close])
        guard !list.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        return splitTopLevel(list).map(parseParameter)
    }

    // MARK: - Private

    /// Parenthesized groups that qualify a name rather than list parameters: `(extension in Module)` and the
    /// private discriminator of `(name in _0123456789ABCDEF)`.
    private static func isNameQualifier(_ content: String) -> Bool {
        if content.hasPrefix("extension in ") {
            return true
        }

        let parts = content.components(separatedBy: " in _")
        guard parts.count == 2, let name = parts.first, let discriminator = parts.last else { return false }

        return !name.isEmpty && !name.contains(" ") && !discriminator.isEmpty && discriminator.allSatisfy(\.isHexDigit)
    }

    private static func parameterListStart(in characters: [Character]) -> Int? {
        var depth = 0
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if depth == 0, character == "(" {
                guard let close = matchingClose(in: characters, from: index) else { return nil }

                if isNameQualifier(String(characters[(index + 1) ..< close])) {
                    index = close + 1
                    continue
                }

                return index
            }

            depth += depthDelta(characters, at: index)
            index += 1
        }

        return nil
    }

    private static func matchingClose(in characters: [Character], from open: Int) -> Int? {
        var depth = 0

        for index in open ..< characters.count {
            if characters[index] == "(" {
                depth += 1
            } else if characters[index] == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }

        return nil
    }

    private static func depthDelta(_ characters: [Character], at index: Int) -> Int {
        switch characters[index] {
        case "(", "[", "<":
            1
        case ")", "]":
            -1
        case ">":
            // The arrow of a function type is not a closing angle bracket.
            index > 0 && characters[index - 1] == "-" ? 0 : -1
        default:
            0
        }
    }

    private static func splitTopLevel(_ list: String) -> [String] {
        let characters = Array(list)
        var parts: [String] = []
        var current = ""
        var depth = 0

        for index in characters.indices {
            let character = characters[index]

            if depth == 0, character == "," {
                parts.append(current)
                current = ""
                continue
            }

            depth += depthDelta(characters, at: index)
            current.append(character)
        }

        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseParameter(_ text: String) -> Parameter {
        // A labeled parameter is `label: Type`; `_` denotes an unlabeled parameter. When none of the parameters of a
        // function have labels, the demangler prints only the types.
        if let separator = text.range(of: ": ") {
            let label = String(text[..<separator.lowerBound])

            if label.first.map({ $0.isLetter || $0 == "_" }) == true,
               label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
            {
                let type = String(text[separator.upperBound...])
                return Parameter(label: label == "_" ? nil : label, type: type)
            }
        }

        return Parameter(label: nil, type: text)
    }
}
