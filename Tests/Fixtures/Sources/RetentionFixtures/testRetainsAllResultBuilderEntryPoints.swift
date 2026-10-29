import Foundation

@resultBuilder
struct FixtureResultBuilderPartial {
    static func buildPartialBlock(first: Int) -> [Int] {
        [first]
    }

    static func buildPartialBlock(accumulated: [Int], next: Int) -> [Int] {
        accumulated + [next]
    }

    static func unusedHelper() {}
}

@resultBuilder
struct FixtureResultBuilderArities {
    static func buildBlock() -> [Int] {
        []
    }

    static func buildBlock(_ first: Int, _ second: Int) -> [Int] {
        [first, second]
    }

    static func buildBlock(_ components: Int...) -> [Int] {
        components
    }

    static func buildBlock<each T>(_ components: repeat each T) -> Int {
        0
    }

    static func buildEither(first: Int) -> Int {
        first
    }

    static func unusedHelper() {}
}

public class FixtureResultBuilderAllEntryPointsRetainer {
    public func build() {
        _ = buildPartial {
            1
            2
        }
        _ = buildArities {}
    }

    func buildPartial(@FixtureResultBuilderPartial _ content: () -> [Int]) -> [Int] {
        content()
    }

    func buildArities(@FixtureResultBuilderArities _ content: () -> [Int]) -> [Int] {
        content()
    }
}
