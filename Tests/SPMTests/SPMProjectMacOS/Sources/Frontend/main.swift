import Foundation
import SPMProjectMacOSKit
import SwiftUI

_ = StateMacroView().$rootRead

@MainActor
func main() {
    // Reference the view controller class (it's also referenced from the xib)
    _ = SPMXibViewController.self
    _ = StateMacroView().body
    _ = SPMImplicitXibViewController.self
}

main()

extension StateMacroView {
    func bindingFromOtherFile() -> Binding<Bool> {
        $crossFile
    }
}
