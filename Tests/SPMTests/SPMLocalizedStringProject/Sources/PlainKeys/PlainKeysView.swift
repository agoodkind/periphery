import AppKit
import SwiftUI

public struct PlainKeysView: View {
    public init() {}

    public var body: some View {
        VStack {
            Text("plain_used_key", bundle: .module)
            Text("plain_text_with_comment_key", bundle: .module, comment: "plain_comment_not_key")
        }
    }
}

public enum PlainKeyCalls {
    public static func use() {
        _ = NSAlert().addButton(withTitle: "plain_objc_callee_key")

        let format: (String) -> String = { $0 }
        _ = format("plain_closure_key")

        run("plain_generic_not_key", completion: { _, _ in }, title: "plain_function_type_title_key")
        privateTitle(title: "plain_private_function_key")
        _ = ternaryTitle(flag: Bool.random())
    }

    static func ternaryTitle(flag: Bool) -> String {
        NSLocalizedString(flag ? "plain_ternary_first_key" : "plain_ternary_second_key", bundle: .module, comment: "")
    }

    static func run(_ value: some StringProtocol, completion: (Int, String) -> Void, title: LocalizedStringResource) {
        _ = value
        completion(0, String(localized: title))
    }

    private static func privateTitle(title: LocalizedStringKey) {
        _ = title
    }
}
