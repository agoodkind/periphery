import SwiftUI

public struct FixtureStruct229: View {
    @State private var onlyBacking = false
    @State private var unusedState = false

    public init() {
        _ = _onlyBacking
    }

    public var body: some View {
        EmptyView()
    }
}
