/// A call whose arguments include static string literals that may be localization keys.
///
/// Whether a literal is a key depends on the type of the parameter that receives it, which is only known once the
/// callee has been resolved from the index store.
public struct LocalizedStringCallSite: Hashable {
    public struct Argument: Hashable {
        public let label: String?
        public let keys: [String]

        public init(label: String?, keys: [String]) {
            self.label = label
            self.keys = keys
        }
    }

    /// The position of the callee name token (e.g. `Button` in `Button("key")`, `navigationTitle` in
    /// `.navigationTitle("key")`), where the index store records the reference to the called function.
    public let line: Int
    public let column: Int
    public let arguments: [Argument]

    public init(line: Int, column: Int, arguments: [Argument]) {
        self.line = line
        self.column = column
        self.arguments = arguments
    }

    public var allKeys: Set<String> {
        Set(arguments.flatMap(\.keys))
    }
}
