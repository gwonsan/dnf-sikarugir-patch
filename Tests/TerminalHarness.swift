import Foundation

private final class SettingsFixtureIO: GameSettingsIO {
    var values: [String:GameSettingsValue] = [:]
    func isGameRunning(wrapper:URL) throws -> Bool { false }
    func read(wrapper:URL) throws -> GameSettingsSnapshot { GameSettingsSnapshot(values:values,globalValues:[:]) }
    func write(_ changes:[String:GameSettingsValue],wrapper:URL) throws { values.merge(changes) { _,new in new } }
}
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
                           keyboardStore: KeyProfileStore(directory:URL(fileURLWithPath:args[1]).deletingLastPathComponent().appendingPathComponent("key-profiles")), activateKeyboard: { _ in }, gameSettings:GameSettingsService(directory:URL(fileURLWithPath:args[1]).deletingLastPathComponent().appendingPathComponent("game-settings"),io:SettingsFixtureIO()),lockDirectory:URL(fileURLWithPath:args[1]).deletingLastPathComponent().appendingPathComponent("locks")).run()
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
