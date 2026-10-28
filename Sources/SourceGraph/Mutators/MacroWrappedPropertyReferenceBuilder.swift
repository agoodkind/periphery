import Configuration
import Foundation
import Shared

/// Since Xcode 27, some SwiftUI attributes such as `@State` are implemented as attached macros. The compiler no
/// longer indexes a use of the projected value (`$foo`) or backing storage (`_foo`) as a reference to the wrapped
/// property (`foo`); it references the separate macro-generated declaration instead. These generated declarations
/// are implicit and therefore always retained, leaving `foo` without references. This mutator forwards each
/// reference to `$foo`/`_foo` onto `foo` so that it's considered used.
final class MacroWrappedPropertyReferenceBuilder: SourceGraphMutator {
    private let graph: SourceGraph
    private let prefixes = ["$", "_"]

    required init(graph: SourceGraph, configuration _: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
    }

    func mutate() {
        let propertyKinds: Set<Declaration.Kind> = [.varInstance, .varStatic, .varClass, .varGlobal]

        for synthesizedDecl in graph.declarations(ofKinds: propertyKinds) where synthesizedDecl.isImplicit {
            guard let prefix = prefixes.first(where: { synthesizedDecl.name.hasPrefix($0) }),
                  let parent = synthesizedDecl.parent
            else { continue }

            let wrappedName = String(synthesizedDecl.name.dropFirst(prefix.count))
            guard !wrappedName.isEmpty, !wrappedName.hasPrefix("_"),
                  let wrappedDecl = parent.declarations.first(where: {
                      $0.name == wrappedName && propertyKinds.contains($0.kind) && !$0.attributes.isEmpty
                  })
            else { continue }

            for synthesizedRef in graph.references(to: synthesizedDecl) {
                // Ignore compiler-synthesized users such as the implicit memberwise initializer, which
                // references `_foo` regardless of whether `foo` is used.
                guard let referencer = synthesizedRef.parent, !referencer.isImplicit else { continue }

                for usr in wrappedDecl.usrs {
                    let ref = Reference(
                        name: wrappedDecl.name,
                        kind: .normal,
                        declarationKind: wrappedDecl.kind,
                        usr: usr,
                        location: synthesizedRef.location
                    )
                    ref.parent = referencer
                    graph.add(ref, from: referencer)
                }
            }
        }
    }
}
