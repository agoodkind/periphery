import Configuration
import Foundation
import Shared

/// Retains localized string declarations from xcstrings files that are used in Swift source code.
///
/// The mutator retains a catalog key when Swift source anywhere in the scan uses it as a static literal or as an
/// interpolated literal with matching format specifiers.
/// It also retains keys that match unresolved lookups in the selected bundle scope.
/// It retains every key when the catalog does not have an owning module or an indexed localized symbol cannot be
/// matched to a generating module. When the generated source is missing, it retains keys in the generating module.
final class LocalizedStringRetainer: SourceGraphMutator {
    /// The regular expression matches one printf-style format specifier, such as `%@`, `%lld`, `%lf`, or `%1$@`.
    /// The Swift compiler writes these specifiers into catalog keys in place of interpolations.
    private static let formatSpecifierPattern = #"%(?:\d+\$)?[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA]"#

    private let graph: SourceGraph

    required init(graph: SourceGraph, configuration _: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
    }

    func mutate() {
        let usedKeys = graph.usedLocalizedStringKeys
        let keyFormats = graph.localizedStringKeyFormats.compactMap(Self.regularExpression(forSegments:))
        let unresolvedPrefixesByModule = graph.unresolvedLocalizedStringKeyPrefixesByModule

        for declaration in graph.declarations(ofKind: .localizedString) {
            let key = declaration.name
            let owningModules = declaration.location.file.modules
            let mainPrefixes: Set<String> = graph.nonMainBundleCatalogs.contains(declaration.location.file.path.lexicallyNormalized())
                ? []
                : graph.mainBundleLocalizedStringKeyPrefixes
            let prefixGroups = [graph.unresolvedLocalizedStringKeyPrefixes, mainPrefixes]
                + owningModules.compactMap { unresolvedPrefixesByModule[$0] }

            if owningModules.isEmpty
                || graph.hasUnresolvedLocalizedSymbol
                || usedKeys.contains(key)
                || keyFormats.contains(where: { Self.matches(key, $0) })
                || prefixGroups.lazy.joined().contains(where: { key.hasPrefix($0) })
            {
                graph.markRetained(declaration)
            }
        }
    }

    // MARK: - Private

    private static func regularExpression(forSegments segments: [String]) -> NSRegularExpression? {
        let escapedSegments = segments.map { NSRegularExpression.escapedPattern(for: $0.replacingOccurrences(of: "%", with: "%%")) }
        let pattern = "^" + escapedSegments.joined(separator: formatSpecifierPattern) + "$"
        return try? NSRegularExpression(pattern: pattern)
    }

    private static func matches(_ key: String, _ expression: NSRegularExpression) -> Bool {
        let range = NSRange(key.startIndex ..< key.endIndex, in: key)
        return expression.firstMatch(in: key, range: range) != nil
    }
}
