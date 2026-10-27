import SwiftUI

public struct FixtureStruct228: View {
    @State private var onlyProjected = false
    @State private var unusedState = false

    public var body: some View {
        Toggle("Toggle", isOn: $onlyProjected)
    }
}
