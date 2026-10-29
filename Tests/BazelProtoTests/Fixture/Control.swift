func usedControl() -> String {
    "The control runs"
}

func unusedControl() -> String {
    "The control is unused"
}

protocol ProtobufAPIVersionCheck {
    associatedtype Version
}

private struct _GeneratedWithProtocGenSwiftVersion: ProtobufAPIVersionCheck {
    struct _2 {}
    typealias Version = _2
}

@main
struct ControlApplication {
    static func main() {
        print(usedControl())
    }
}
