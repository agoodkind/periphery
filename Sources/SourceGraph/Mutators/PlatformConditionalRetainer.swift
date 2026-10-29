import Configuration
import Foundation
import Shared

/// The index store only describes the platform it was built for, so code that is only reachable on another
/// platform appears unused. This retains:
///  - declarations marked `@available(<platform>, unavailable)`, as they exist for other platforms, and
///  - declarations whose name is written inside a platform conditional `#if` block, as the reference may live
///    in a branch that was not compiled.
final class PlatformConditionalRetainer: SourceGraphMutator {
    private static let nonReferenceableKinds: Set<Declaration.Kind> = [
        .module, .extension, .extensionClass, .extensionEnum, .extensionProtocol, .extensionStruct,
        .functionConstructor, .functionDestructor, .varParameter, .varLocal, .genericTypeParam,
        .functionAccessorAddress, .functionAccessorDidset, .functionAccessorGetter, .functionAccessorMutableaddress,
        .functionAccessorSetter, .functionAccessorWillset, .functionAccessorRead, .functionAccessorModify,
        .functionAccessorInit,
    ]

    private let graph: SourceGraph
    private let configuration: Configuration

    required init(graph: SourceGraph, configuration: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
        self.configuration = configuration
    }

    func mutate() {
        guard !configuration.disablePlatformConditionalRetention else { return }

        let names = graph.platformConditionalNames

        for decl in graph.allDeclarations {
            if isUnavailableOnPlatform(decl) {
                graph.markRetained(decl)
                graph.markRetained(decl.descendentDeclarations)
            } else if !names.isEmpty,
                      !Self.nonReferenceableKinds.contains(decl.kind),
                      names.contains(Self.baseName(of: decl.name))
            {
                graph.markRetained(decl)
            }
        }
    }

    // MARK: - Private

    private static func baseName(of declarationName: String) -> String {
        declarationName.prefix { $0 != "(" }.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
    }

    private static func removingStringLiterals(from arguments: String) -> String {
        var result = ""
        var isInsideString = false
        var isEscaped = false

        for character in arguments {
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else {
                result.append(character)
            }
        }

        return result
    }

    private func isUnavailableOnPlatform(_ decl: Declaration) -> Bool {
        decl.attributes.contains { attribute in
            guard attribute.name == "available", let arguments = attribute.arguments else { return false }

            let parts = Self.removingStringLiterals(from: arguments)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            guard let platform = parts.first,
                  platform != "*",
                  platform != "swift",
                  !platform.hasSuffix("ApplicationExtension")
            else { return false }

            return parts.dropFirst().contains("unavailable")
        }
    }
}
