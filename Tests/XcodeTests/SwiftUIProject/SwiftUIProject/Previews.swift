import SwiftUI

struct PreviewOnlyView: View {
    var body: some View {
        Text("Hello, world!")
    }
}

struct PreviewOnlyView_PreviewProvider: PreviewProvider {
    static var previews: some View {
        PreviewOnlyView()
    }
}

#Preview {
    PreviewOnlyView()
}

enum LivePreviewSampleData {
    static let title = "Sample"
}

#Preview("Live") {
    VStack {
        ContentView()
        Text(LivePreviewSampleData.title)
    }
}

struct DeadPreviewedView: View {
    let title: String

    var body: some View {
        Text(title)
    }
}

enum DeadPreviewSampleData {
    static let title = "Dead"
}

#Preview("Dead") {
    DeadPreviewedView(title: DeadPreviewSampleData.title + String(describing: AppDelegate.self))
}
