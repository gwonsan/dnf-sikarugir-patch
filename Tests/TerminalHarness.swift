import Foundation

@main struct TerminalHarness {
    static func main() {
        let args = CommandLine.arguments
        var snapshot = MenuSnapshot()
        snapshot.wrapperPath = "/tmp/Test Game.app"
        snapshot.wrapperExists = true
        snapshot.wineAvailable = true
        snapshot.recorded = true
        snapshot.appleSilicon = true
        snapshot.metal = true
        do {
            try TerminalUI(root: URL(fileURLWithPath: "/tmp/Test Package"),
                           helper: URL(fileURLWithPath: args[1]),
                           snapshot: { snapshot }, openHomepage: { true },
                           keyboardStore: KeyProfileStore(directory:URL(fileURLWithPath:args[1]).deletingLastPathComponent().appendingPathComponent("key-profiles")), activateKeyboard: { _ in }).run()
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
