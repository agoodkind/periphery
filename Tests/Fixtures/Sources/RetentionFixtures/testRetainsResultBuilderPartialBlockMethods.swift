import Foundation

@resultBuilder
struct FixtureStruct225 {
    static func buildPartialBlock(first: Int) -> [Int] {
        [first]
    }

    static func buildPartialBlock(accumulated: [Int], next: Int) -> [Int] {
        accumulated + [next]
    }

    static func unusedMethod() -> [Int] {
        []
    }
}

@resultBuilder
struct FixtureStruct226 {
    static func buildPartialBlock(first: Int) -> [Int] {
        [first]
    }

    static func buildPartialBlock(accumulated: [Int], next: Int) -> [Int] {
        accumulated + [next]
    }
}

public class FixtureStruct225Retainer {
    public func build() {
        _ = buildNonPublic { 1 }
    }

    func buildNonPublic(@FixtureStruct225 _ content: () -> [Int]) -> [Int] {
        content()
    }
}
