import SwiftUI

public struct FixtureStruct230: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismiss) private var unusedEnvironment
    @FocusState private var focused: Bool
    @FocusState private var unusedFocus: Bool
    @AppStorage("key") private var stored = false
    @AppStorage("unused") private var unusedStored = false
    @SceneStorage("key") private var scene = false
    @StateObject private var model = FixtureClass230()
    @Binding private var binding: Bool

    public init(binding: Binding<Bool>) {
        _binding = binding
    }

    public var body: some View {
        VStack {
            Toggle("Toggle", isOn: $stored)
            Toggle("Toggle", isOn: $scene)
            Toggle("Toggle", isOn: $binding)
            Toggle("Toggle", isOn: $focused.bindingValue)
            Text("\(model.value.description)")
        }
        .onTapGesture { dismiss() }
    }
}

extension FocusState<Bool>.Binding {
    var bindingValue: Binding<Bool> { Binding(get: { wrappedValue }, set: { wrappedValue = $0 }) }
}

public final class FixtureClass230: ObservableObject {
    @Published var value = false
}
