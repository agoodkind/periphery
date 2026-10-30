import Owner
import SwiftUI

@main
struct App: SwiftUI.App {
    var body: some Scene {
        WindowGroup {
            Text(String(localized: Owner.title))
        }
    }
}
