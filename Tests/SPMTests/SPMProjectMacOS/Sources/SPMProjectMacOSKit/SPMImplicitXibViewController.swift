import AppKit

// The companion xib sits outside `Resources/`, so SwiftPM processes it implicitly without a
// `resources:` declaration, and `swift package describe` does not list it.
public final class SPMImplicitXibViewController: NSViewController {
    // MARK: - Referenced via XIB (connected)

    @IBOutlet private var privateButton: NSButton!

    @IBAction private func privateButtonTapped(_: Any) {}

    @IBInspectable private var privateBorderWidth: CGFloat = 0

    // MARK: - Unreferenced (not connected in XIB)

    @IBOutlet private var unusedPrivateOutlet: NSTextField!

    @IBAction private func unusedPrivateAction(_: Any) {}

    @IBInspectable private var unusedPrivateInspectable: CGFloat = 0
}

private extension SPMImplicitXibViewController {
    // MARK: - Referenced via XIB (connected)

    @IBAction func extensionButtonTapped(_: Any) {}

    // MARK: - Unreferenced (not connected in XIB)

    @IBAction func unusedExtensionAction(_: Any) {}
}
