import Foundation

public enum MixedKeys {
    public static func title(flag: Bool, keyName: String) -> String {
        NSLocalizedString(flag ? "mixed_known_key" : keyName, bundle: .module, comment: "")
    }
}
