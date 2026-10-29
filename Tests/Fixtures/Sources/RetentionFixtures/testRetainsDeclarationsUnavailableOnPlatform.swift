import Foundation

public class FixtureClass223 {
    @available(iOS, unavailable)
    func unavailableOnIOS() {}

    @available(macOS, unavailable, message: "Use another, unavailable elsewhere")
    func unavailableOnMacOS() {}

    @available(tvOS, unavailable)
    func unavailableOnTvOS() {}

    @available(macOS 13, *)
    func introducedOnMacOS() {}

    func unusedMethod() {}
}

@available(watchOS, unavailable)
class FixtureClass224 {
    func someMethod() {}
}
