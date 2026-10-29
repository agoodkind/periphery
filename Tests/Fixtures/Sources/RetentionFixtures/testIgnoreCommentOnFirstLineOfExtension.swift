import Foundation

extension String { // periphery:ignore
    subscript(_ fixtureIssue9Index: Int) -> Character {
        self[index(startIndex, offsetBy: fixtureIssue9Index)]
    }

    init(fixtureIssue9Value: Int) {
        self = "\(fixtureIssue9Value)"
    }

    var fixtureIssue9Computed: Int {
        get { count }
        set { _ = newValue }
    }

    static func - (lhs: String, rhs: String) -> String {
        lhs + rhs
    }

    func fixtureIssue9Func() {}
}

// periphery:ignore
extension Int {
    subscript(fixtureIssue9Offset offset: Int) -> Int {
        self + offset
    }

    func fixtureIssue9IntFunc() {}
}

struct FixtureIssue9Struct { // periphery:ignore
    subscript(_ fixtureIssue9Index: Int) -> Int {
        fixtureIssue9Index
    }

    func fixtureIssue9StructFunc() {}
}

class FixtureIssue9Class { // periphery:ignore
    deinit {}

    subscript(_ fixtureIssue9Index: Int) -> Int {
        fixtureIssue9Index
    }
}

extension Double {
    subscript(fixtureIssue9Control index: Int) -> Int {
        index
    }

    func fixtureIssue9ControlFunc() {}
}

extension Array where Element == Int { // periphery:ignore
    subscript(fixtureIssue9Safe index: Int) -> Int? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Set<String> { // periphery:ignore
    subscript(fixtureIssue9Member member: String) -> Bool {
        contains(member)
    }
}

// Exact snippet from upstream issue #1113 (tabs, sole member, unnamed parameter).
extension Substring { // periphery:ignore
	subscript(_: Int) -> Self {
		self
	}
}
