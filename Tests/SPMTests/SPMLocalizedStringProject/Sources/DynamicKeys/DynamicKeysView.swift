import SwiftUI

public struct DynamicKeysView: View {
    let keyName: String

    public init(keyName: String) {
        self.keyName = keyName
    }

    public var body: some View {
        VStack {
            Text("dynamic_plain_key", bundle: .module)
            Text(LocalizedStringKey(keyName), bundle: .module)
        }
    }
}
