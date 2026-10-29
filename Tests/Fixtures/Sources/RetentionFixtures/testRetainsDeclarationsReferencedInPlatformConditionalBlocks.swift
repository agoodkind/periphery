import Foundation

public class FixtureClass225 {
    private func onlyUsedOnIOS() {}
    private var onlyUsedOnIOSProperty = 1
    private func onlyUsedOnWindows() {}
    private func onlyUsedUnderCustomFlag() {}
    private func unusedMethod() {}

    public func entry() {
        #if os(iOS)
        onlyUsedOnIOS()
        _ = onlyUsedOnIOSProperty
        #elseif os(Windows)
        onlyUsedOnWindows()
        #endif

        #if FIXTURE_UNDEFINED_FLAG
        onlyUsedUnderCustomFlag()
        #endif
    }
}
