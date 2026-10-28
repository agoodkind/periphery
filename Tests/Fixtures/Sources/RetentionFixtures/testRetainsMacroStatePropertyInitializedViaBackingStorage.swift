import SwiftUI

public struct FixtureStruct231: View {
    @State private var assignedViaBacking: Bool

    public init(flag: Bool) {
        _assignedViaBacking = State(wrappedValue: flag)
    }

    public var body: some View {
        EmptyView()
    }
}
