import AppKit

@main
enum ExampleApplication {
    static func main() {
        let application = NSApplication.shared
        print(usedGreeting())
        application.run()
    }
}
