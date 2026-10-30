import Foundation

public let ownerBundle = Bundle.module

public func localLookup(_ suffix: String) -> String {
    NSLocalizedString("local." + suffix, bundle: .module, comment: "")
}
