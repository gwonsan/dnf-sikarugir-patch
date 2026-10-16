import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { print("FAIL: \(message)"); exit(1) }
}

@main struct RecoveryTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DNF recovery \(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let stateFile = root.appendingPathComponent("state.plist")
        let wrapper = root.appendingPathComponent("Removed.app")
        let destination = root.appendingPathComponent("Helper.app")
        let state = PatchState(wrapperPath: wrapper.path, previousHandler: "fixture.previous", originalFonts: ["Arial": "original"], installed: true)
        let original = try PropertyListEncoder().encode(state)
        try original.write(to: stateFile)
        var handlerRestored = false
        do {
            try Installer.restoreInstallation(state, stateFile: stateFile, destination: destination, restoreFonts: { _, _ in
                throw PatchError(message: "Wine is missing")
            }, restoreHandler: { saved in
                check(saved.previousHandler == "fixture.previous", "restore the saved handler")
                handlerRestored = true
            })
        } catch {
            print("FAIL: a missing wrapper must not trap restoration: \(error.localizedDescription)")
            exit(1)
        }
        check(handlerRestored && !fm.fileExists(atPath: stateFile.path), "clear stale state after restoring the connection")
        check(!fm.fileExists(atPath: wrapper.path), "restoring must not recreate a missing app")
        let backups = try fm.contentsOfDirectory(at: root.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        check(backups.count == 1, "preserve the missing app's font backup")
        let backup = try Data(contentsOf: backups[0])
        check(backup == original, "keep the original state intact for a moved app")
        let permissions = try fm.attributesOfItem(atPath: backups[0].path)[.posixPermissions] as? NSNumber
        check(permissions?.intValue == 0o600, "recovery backup is private")

        // Existing but broken Wine must not silently discard font restoration.
        try fm.createDirectory(at: wrapper, withIntermediateDirectories: true)
        let game = wrapper.appendingPathComponent("game-data")
        try Data("keep".utf8).write(to: game)
        try original.write(to: stateFile)
        handlerRestored = false
        do {
            try Installer.restoreInstallation(state, stateFile: stateFile, destination: destination, restoreFonts: { _, _ in
                throw PatchError(message: "Wine failed")
            }, restoreHandler: { _ in handlerRestored = true })
            check(false, "normal restoration must report Wine failure")
        } catch {}
        check(!handlerRestored && fm.fileExists(atPath: stateFile.path), "failed font restore retains the state and handler")
        do {
            try Installer.restoreInstallation(state, stateFile: stateFile, destination: destination, restoreFonts: { app, saved in
            check(app.path == wrapper.path && saved.originalFonts["Arial"] == "original", "normal restore uses the saved font snapshot")
            }, restoreHandler: { _ in throw PatchError(message: "handler unavailable") })
            check(false, "failed handler restoration must report failure")
        } catch {}
        check(fm.fileExists(atPath: stateFile.path), "handler failure keeps the state for retry")
        // Explicit connection-only recovery must not call Wine in a broken app.
        try fm.createDirectory(at: destination.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info: [String: String] = ["CFBundleIdentifier": patchBundleID, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: destination.appendingPathComponent("Contents/Info.plist"))
        handlerRestored = false
        try Installer.restoreInstallation(state, stateFile: stateFile, destination: destination, connectionOnly: true, restoreFonts: { _, _ in
            throw PatchError(message: "connection-only recovery must not invoke Wine")
        }, restoreHandler: { _ in handlerRestored = true })
        check(handlerRestored && !fm.fileExists(atPath: stateFile.path), "explicit recovery clears stale state")
        check(!fm.fileExists(atPath: destination.path), "remove only the owned helper after handler restoration")
        let savedBackups = try fm.contentsOfDirectory(at: root.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        check(savedBackups.count == 2, "connection-only recovery also preserves its font backup")

        // Normal restoration still restores fonts first and preserves unrelated helper paths.
        try original.write(to: stateFile)
        let unrelated = root.appendingPathComponent("Unrelated.app")
        try fm.createDirectory(at: unrelated, withIntermediateDirectories: true)
        var fontsRestored = false
        try Installer.restoreInstallation(state, stateFile: stateFile, destination: unrelated, restoreFonts: { _, _ in
            fontsRestored = true
        }, restoreHandler: { _ in check(fontsRestored, "restore fonts before the handler") })
        check(fontsRestored && !fm.fileExists(atPath: stateFile.path), "normal restoration completes")
        check(fm.fileExists(atPath: unrelated.path), "never remove an unrelated app")
        let gameData = try Data(contentsOf: game)
        check(gameData == Data("keep".utf8), "recovery never deletes game data")
        print("PASS: missing wrapper recovery, backup, existing Wine failure and handler failure")
    }
}
