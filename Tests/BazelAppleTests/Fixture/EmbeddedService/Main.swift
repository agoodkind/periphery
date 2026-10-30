@main
enum EmbeddedService {
    static func main() {
        print(serviceMessage())
    }

    static func serviceMessage() -> String {
        "Embedded service"
    }
}
