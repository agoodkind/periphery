//
//  StateMacroView.swift
//  SPMProjectMacOS
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-10-27
//

import SwiftUI

struct StateMacroView: View {
    @State private var projected = false
    @State private var direct = false
    @State private var backing = false
    @SwiftUI.State
    private var qualified = false
    @State var crossFile = false
    @State private var unused = false
    @State private var deadBinding = false

    // Keep synthesized initializer parameters from referencing the state properties.
    init() {}

    var body: some View {
        VStack {
            Toggle("Projected", isOn: $projected)
            Text(direct.description)
            Text(_backing.wrappedValue.description)
            Toggle("Qualified", isOn: $qualified)
            Toggle("Cross file", isOn: bindingFromOtherFile())
        }
    }

    private func unusedBinding() -> Binding<Bool> {
        $deadBinding
    }
}
