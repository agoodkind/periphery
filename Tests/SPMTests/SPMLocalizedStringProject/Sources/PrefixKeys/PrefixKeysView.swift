import SwiftUI

public struct PrefixKeysView: View {
    let suffix: String

    public init(suffix: String) {
        self.suffix = suffix
    }

    public var body: some View {
        Text(LocalizedStringKey("settings." + suffix), bundle: .module)
    }
}
