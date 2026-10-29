import Foundation

public struct FixtureStruct232 {
    func render() {}
}

public struct FixtureStruct233 {
    func render() {}
}

public class FixtureClass232 {
    private func onlyUsedOnIOS() {}
    private func unusedMethod() {}

    public func entry() {
        #if os(iOS)
        FixtureStruct232().render()
        onlyUsedOnIOS()
        #endif
    }
}
