import Foundation

public class FixtureClass236 {
    #if canImport(Foundation)
    public func entry() -> Int {
        usedInsideBlock()
    }

    private func usedInsideBlock() -> Int {
        1
    }

    private func unusedInsideBlock() -> Int {
        2
    }
    #endif
}
