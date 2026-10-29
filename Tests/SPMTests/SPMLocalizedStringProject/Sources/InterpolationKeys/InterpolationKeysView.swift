import SwiftUI

public struct InterpolationKeysView: View {
    let count: Int
    let name: String
    let ratio: Double

    public init(count: Int, name: String, ratio: Double) {
        self.count = count
        self.name = name
        self.ratio = ratio
    }

    public var body: some View {
        VStack {
            Text("interpolation_count \(count) items", bundle: .module)
            Text("interpolation_greeting \(name)", bundle: .module)
            Text("interpolation_ratio \(ratio)", bundle: .module)
        }
    }
}
