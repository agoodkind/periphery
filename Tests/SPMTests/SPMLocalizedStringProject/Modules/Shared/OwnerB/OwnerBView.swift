import SwiftUI

public struct OwnerBView: View {
    let keyName: String

    public init(keyName: String) {
        self.keyName = keyName
    }

    public var body: some View {
        Text(LocalizedStringKey(keyName))
    }
}
