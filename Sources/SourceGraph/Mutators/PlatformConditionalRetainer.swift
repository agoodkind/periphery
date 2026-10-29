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
    private static let typeKinds: Set<Declaration.Kind> = [
        .class, .struct, .enum, .protocol, .typealias,
        .extensionClass, .extensionEnum, .extensionProtocol, .extensionStruct,
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
        let declarationCounts = countReferenceableDeclarations(named: names)
        let typeNames = typeDeclarationNames()

        for decl in graph.allDeclarations {
            if isUnavailableOnPlatform(decl) {
                graph.markRetained(decl)
                graph.markRetained(decl.descendentDeclarations)
            } else if !Self.nonReferenceableKinds.contains(decl.kind),
                      let use = names[Self.baseName(of: decl.name)],
                      isReferenced(decl, use: use, declarationCounts: declarationCounts, typeNames: typeNames)
            {
                graph.markRetained(decl)
            }
        }
    }

    // MARK: - Private

    private func countReferenceableDeclarations(named names: [String: PlatformConditionalNameUse]) -> [String: Int] {
        var counts: [String: Int] = [:]
        guard !names.isEmpty else { return counts }

        for decl in graph.allDeclarations where !Self.nonReferenceableKinds.contains(decl.kind) {
            let baseName = Self.baseName(of: decl.name)

            if names[baseName] != nil {
                counts[baseName, default: 0] += 1
            }
        }

        return counts
    }

    private func typeDeclarationNames() -> Set<String> {
        graph.declarations(ofKinds: Self.typeKinds).mapSet { Self.baseName(of: $0.name) }
    }

    /// The function checks declarations with a base name used in inactive platform-conditional code.
    /// When multiple referenceable declarations share that name, it restricts matches only if every reference states a
    /// receiver and every receiver identifies a scanned type or extension.
    /// Under those conditions, it returns `true` only for members of recorded receiver types; otherwise, it returns
    /// `true` for every declaration with that name.
    private func isReferenced(
        _ decl: Declaration,
        use: PlatformConditionalNameUse,
        declarationCounts: [String: Int],
        typeNames: Set<String>
    ) -> Bool {
        let baseName = Self.baseName(of: decl.name)
        guard declarationCounts[baseName, default: 0] > 1,
              !use.hasUnknownReceiver,
              use.receiverNames.isSubset(of: typeNames),
              let parent = decl.parent
        else { return true }

        return use.receiverNames.contains(Self.baseName(of: parent.name))
    }

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
