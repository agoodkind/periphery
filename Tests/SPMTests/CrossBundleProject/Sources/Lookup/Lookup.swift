import Foundation

public func lookup(_ key: String, bundle: Bundle) -> String {
    bundle.localizedString(forKey: "dynamic." + key.dropFirst("dynamic.".count), value: nil, table: nil)
}
