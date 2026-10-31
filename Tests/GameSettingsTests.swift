import Foundation

private func check(_ value: @autoclosure () throws -> Bool, _ message: String) {
    do { guard try value() else { fputs("FAIL: \(message)\n", stderr); exit(1) } }
    catch { fputs("FAIL: \(message): \(error)\n", stderr); exit(1) }
}
private final class SettingsFixture: GameSettingsIO {
    var running = false
    var values = GameSettingsSnapshot(values: ["LeftCommandIsCtrl": .absent, "RightCommandIsCtrl": .absent,
        "LeftOptionIsAlt": .absent, "RightOptionIsAlt": .absent, "D3DMETAL": .boolean(true), "CNC_DDRAW": .boolean(false)],
        globalValues: ["LeftCommandIsCtrl": "Y", "RightCommandIsCtrl": "Y", "LeftOptionIsAlt": "Y", "RightOptionIsAlt": "Y"])
    var writes = 0
    var failAfterWrite = false
    var failBeforeWrite = false
    func isGameRunning(wrapper: URL) throws -> Bool { running }
    func read(wrapper: URL) throws -> GameSettingsSnapshot { values }
    func write(_ changes: [String: GameSettingsValue], wrapper: URL) throws {
        check(!running, "no engine mutation while game is running")
        writes += 1
        if failBeforeWrite { throw NSError(domain: "fixture-before", code: 1) }
        for (key, value) in changes { values.values[key] = value }
        if failAfterWrite { throw NSError(domain: "fixture", code: 1) }
    }
}

@main struct GameSettingsTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DNF settings \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let wrapper = root.appendingPathComponent("Game with spaces.app")
        let fixture = SettingsFixture()
        let service = GameSettingsService(directory: root.appendingPathComponent("settings"), io: fixture)
        let initial = try service.read(wrapper: wrapper)
        check(initial == GameSettings(commandToControl: true, leftOptionIsAlt: true, rightOptionIsAlt: true, d3dMetal: true, cncDDraw: false), "current settings resolve app values over global fallback")
        var desired = initial; desired.commandToControl = false; desired.rightOptionIsAlt = false; desired.cncDDraw = true
        try service.save(desired, wrapper: wrapper)
        let saved = try service.read(wrapper: wrapper)
        check(saved == desired, "saving exposes persisted desired settings")
        check(fixture.writes == 0, "save changes no live Wine or renderer values")
        check(try service.hasPending(wrapper: wrapper), "saved change is pending")
        fixture.running = true
        check(try !service.applyPending(wrapper: wrapper), "active game defers application")
        check(fixture.writes == 0, "active game never starts a registry mutation")
        check(try !service.restore(wrapper: wrapper), "active game defers restoration")
        fixture.running = false
        check(try service.applyPending(wrapper: wrapper), "closed game applies pending settings")
        check(fixture.values.values["LeftCommandIsCtrl"] == .string("N") && fixture.values.values["RightCommandIsCtrl"] == .string("N"), "both Command sides are app-specific REG_SZ N")
        check(fixture.values.values["RightOptionIsAlt"] == .string("N") && fixture.values.values["D3DMETAL"] == .boolean(true) && fixture.values.values["CNC_DDRAW"] == .boolean(true), "Option and renderer settings apply")
        check(try !service.hasPending(wrapper: wrapper), "application clears pending state")
        let afterFirst = fixture.writes
        check(try service.applyPending(wrapper: wrapper) && fixture.writes == afterFirst, "idempotent application performs no writes")
        let other = root.appendingPathComponent("Other.app")
        check(try !service.hasPending(wrapper: other), "per-wrapper intent never leaks")
        fixture.values.values["LeftCommandIsCtrl"] = .string("Y")
        fixture.values.values["CNC_DDRAW"] = .boolean(false)
        check(try service.restore(wrapper: wrapper), "restoration succeeds")
        check(fixture.values.values["LeftCommandIsCtrl"] == .string("Y"), "restoration preserves later user Command edit")
        check(fixture.values.values["RightCommandIsCtrl"] == .absent && fixture.values.values["RightOptionIsAlt"] == .absent, "restoration deletes only owned app overrides originally absent")
        check(fixture.values.values["CNC_DDRAW"] == .boolean(false), "restoration preserves later renderer edit")
        check(try !service.hasPending(wrapper: wrapper), "restoration cancels desired settings")
        check(try service.read(wrapper: wrapper) == initial, "restored settings use global fallback")

        // Reapply owns a new baseline if another tool/user changed an owned field.
        try service.save(desired, wrapper: wrapper); _ = try service.applyPending(wrapper: wrapper)
        fixture.values.values["RightCommandIsCtrl"] = .string("Y")
        var revised = desired; revised.d3dMetal = false
        try service.save(revised, wrapper: wrapper); _ = try service.applyPending(wrapper: wrapper)
        _ = try service.restore(wrapper: wrapper)
        check(fixture.values.values["RightCommandIsCtrl"] == .string("Y"), "reapply retains a later external value as restoration baseline")
        check(fixture.values.values["D3DMETAL"] == .boolean(true), "reapply retains the first original for still-owned values")

        let failedIO = SettingsFixture()
        let failedService = GameSettingsService(directory: root.appendingPathComponent("failed"), io: failedIO)
        try failedService.save(desired, wrapper: wrapper)
        failedIO.failAfterWrite = true
        do { _ = try failedService.applyPending(wrapper: wrapper); check(false, "fixture application must fail") } catch {}
        check(try failedService.hasPending(wrapper: wrapper), "failed writes remain pending even if values reached the target")
        failedIO.failAfterWrite = false
        _ = try failedService.restore(wrapper: wrapper)
        check(failedIO.values.values["RightCommandIsCtrl"] == .absent && failedIO.values.values["CNC_DDRAW"] == .boolean(false), "durable intent permits restoration after a partial operation")

        // Adopt the actual older minimal backup shape, never the global baseline.
        let legacy = root.appendingPathComponent("legacy/command-control-original.json")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacyData: [String: Any] = ["wrapperPath": wrapper.path, "appValues": [:], "globalValues": ["LeftCommandIsCtrl": "\"Y\""], "time": "2026-10-27T23:36:31.451384"]
        try JSONSerialization.data(withJSONObject: legacyData).write(to: legacy)
        let legacyIO = SettingsFixture(); legacyIO.values.values["LeftCommandIsCtrl"] = .string("N"); legacyIO.values.values["RightCommandIsCtrl"] = .string("N")
        let legacyService = GameSettingsService(directory: root.appendingPathComponent("legacy/new"), io: legacyIO, legacyBackup: legacy)
        _ = try legacyService.restore(wrapper: wrapper)
        check(legacyIO.values.values["LeftCommandIsCtrl"] == .absent && legacyIO.values.values["RightCommandIsCtrl"] == .absent, "same-wrapper owned N adopts absent app originals")
        legacyIO.values.values["LeftCommandIsCtrl"] = .string("N"); legacyIO.values.values["RightCommandIsCtrl"] = .string("N")
        let unrelated = GameSettingsService(directory: root.appendingPathComponent("legacy/other"), io: legacyIO, legacyBackup: legacy)
        _ = try unrelated.restore(wrapper: other)
        check(legacyIO.values.values["LeftCommandIsCtrl"] == .string("N"), "legacy backup from another wrapper is never adopted")
        legacyIO.values.values["LeftCommandIsCtrl"] = .string("Y")
        let changed = GameSettingsService(directory: root.appendingPathComponent("legacy/changed"), io: legacyIO, legacyBackup: legacy)
        _ = try changed.restore(wrapper: wrapper)
        check(legacyIO.values.values["LeftCommandIsCtrl"] == .string("Y") && legacyIO.values.values["RightCommandIsCtrl"] == .absent, "legacy adoption owns only unchanged N sides")

        try testFailedReapply(root: root, wrapper: wrapper, initial: initial)
        try testFileEngine(root: root)
        print("GameSettingsTests passed")
    }

    private static func testFailedReapply(root: URL, wrapper: URL, initial: GameSettings) throws {
        var commandN = initial; commandN.commandToControl = false
        var commandY = commandN; commandY.commandToControl = true
        let io = SettingsFixture()
        let directory = root.appendingPathComponent("failed-reapply")
        var service = GameSettingsService(directory: directory, io: io)
        try service.save(commandN, wrapper: wrapper); _ = try service.applyPending(wrapper: wrapper)
        try service.save(commandY, wrapper: wrapper)
        io.failBeforeWrite = true
        do { _ = try service.applyPending(wrapper: wrapper); check(false, "reapply must fail before changing Wine") } catch {}
        io.failBeforeWrite = false
        service = GameSettingsService(directory: directory, io: io)
        _ = try service.restore(wrapper: wrapper)
        check(io.values.values["LeftCommandIsCtrl"] == .absent && io.values.values["RightCommandIsCtrl"] == .absent,
              "failed reapply preserves ownership of the prior live value across restart")

        // Several incomplete attempts may leave different keys at different attempt values.
        try service.save(commandN, wrapper: wrapper); _ = try service.applyPending(wrapper: wrapper)
        try service.save(commandY, wrapper: wrapper)
        io.failBeforeWrite = true
        do { _ = try service.applyPending(wrapper: wrapper); check(false, "first interrupted retry must fail") } catch {}
        var revised = commandY; revised.rightOptionIsAlt = false; revised.cncDDraw = true
        try service.save(revised, wrapper: wrapper)
        io.failBeforeWrite = false; io.failAfterWrite = true
        do { _ = try service.applyPending(wrapper: wrapper); check(false, "second interrupted retry must fail after mutation") } catch {}
        io.failAfterWrite = false
        io.values.values["LeftOptionIsAlt"] = .string("external")
        service = GameSettingsService(directory: directory, io: io)
        _ = try service.restore(wrapper: wrapper)
        check(io.values.values["LeftCommandIsCtrl"] == .absent && io.values.values["RightCommandIsCtrl"] == .absent,
              "retry seeing a previously owned value retains the original absent baseline")
        check(io.values.values["RightOptionIsAlt"] == .absent && io.values.values["CNC_DDRAW"] == .boolean(false),
              "restoration owns the values written by a later incomplete attempt")
        check(io.values.values["LeftOptionIsAlt"] == .string("external"), "incomplete-attempt restoration preserves a true external edit")

        try service.save(commandN, wrapper: wrapper); _ = try service.applyPending(wrapper: wrapper)
        try service.save(commandY, wrapper: wrapper)
        io.failBeforeWrite = true
        do { _ = try service.applyPending(wrapper: wrapper); check(false, "third interrupted retry must fail") } catch {}
        var next = commandN; next.rightOptionIsAlt = false
        try service.save(next, wrapper: wrapper)
        do { _ = try service.applyPending(wrapper: wrapper); check(false, "fourth interrupted retry must fail") } catch {}
        try service.save(commandN, wrapper: wrapper)
        check(try service.hasPending(wrapper: wrapper), "returning to committed settings remains pending while an attempt is incomplete")
        io.failBeforeWrite = false
        io.values.values["RightCommandIsCtrl"] = .string("external")
        _ = try service.applyPending(wrapper: wrapper)
        check(try !service.hasPending(wrapper: wrapper), "a complete retry clears incomplete ownership history")
        // Y was attempted but never written; a completed N commit releases that old attempt.
        io.values.values["LeftCommandIsCtrl"] = .string("Y")
        _ = try service.restore(wrapper: wrapper)
        check(io.values.values["LeftCommandIsCtrl"] == .string("Y"), "successful commit releases ownership of superseded attempted values")
        check(io.values.values["RightCommandIsCtrl"] == .string("external"), "successful retry adopts a true external value as its new restoration baseline")
    }

    private static func testFileEngine(root: URL) throws {
        let wrapper = root.appendingPathComponent("Offline.app")
        let prefix = wrapper.appendingPathComponent("Contents/SharedSupport/prefix")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let registry = #"""
        WINE REGISTRY Version 2
        [Software\\Wine\\Mac Driver] 100
        "LeftCommandIsCtrl"="Y"
        "RightCommandIsCtrl"="Y"
        "LeftOptionIsAlt"="Y"
        "RightOptionIsAlt"="Y"
        [Software\\Wine\\AppDefaults\\Other.exe\\Mac Driver] 100
        "LeftCommandIsCtrl"="N"
        [software\\wine\\appdefaults\\dnf.exe\\mac driver] 100
        "rightcommandisctrl"="N"
        "RightOptionIsAlt"="N"
        [Software\\Unrelated\\Secrets] 100
        "Authentication"="never-return-this"
        "LeftCommandIsCtrl"="N"
        """#
        try registry.write(to: prefix.appendingPathComponent("user.reg"), atomically: true, encoding: .utf8)
        let info = wrapper.appendingPathComponent("Contents/Info.plist")
        try PropertyListSerialization.data(fromPropertyList: ["D3DMETAL": true, "CNC_DDRAW": false, "D9VK": true, "Unrelated": "preserve"], format: .xml, options: 0).write(to: info)
        let io = WineGameSettingsIO(gameRunning: { _ in false })
        let snapshot = try io.read(wrapper: wrapper)
        check(snapshot.values["LeftCommandIsCtrl"] == .absent && snapshot.values["RightCommandIsCtrl"] == .string("N"), "offline registry parser isolates the exact DNF app section")
        check(snapshot.globalValues["LeftCommandIsCtrl"] == "Y" && snapshot.globalValues.count == 4, "offline parser returns only allowed global keys")
        check(snapshot.values.count == 6 && !snapshot.values.description.contains("never-return-this"), "snapshot excludes unrelated registry and authentication data")
        let queryIO = WineGameSettingsIO(gameRunning: { _ in false }, wineProcess: { args, _ in
            check(args == ["C:\\windows\\system32\\reg.exe", "query", "HKCU\\Software\\Wine\\AppDefaults\\DNF.exe\\Mac Driver"], "mutation snapshot queries only the DNF Mac Driver key")
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/echo")
            process.arguments = ["HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\DNF.exe\\Mac Driver\n    LeftCommandIsCtrl    REG_SZ    N\n    RightCommandIsCtrl    REG_SZ    Y\n    Secret    REG_SZ    never-return-live-this"]
            return process
        })
        let authoritative = try queryIO.readForMutation(wrapper: wrapper)
        check(authoritative.values["LeftCommandIsCtrl"] == .string("N") && authoritative.values["RightCommandIsCtrl"] == .string("Y"), "mutation reads authoritative Wine values when user.reg has not flushed")
        check(!authoritative.values.description.contains("never-return-live-this"), "targeted registry query filters unrelated values")
        var importText = ""
        let importIO = WineGameSettingsIO(gameRunning: { _ in false }, wineProcess: { args, target in
            check(args.count == 3 && args[0] == "C:\\windows\\system32\\reg.exe" && args[1] == "import", "mutation uses reg import only")
            let name = args[2].split(separator: "\\").last!
            let file = target.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/windows/temp/" + name)
            importText = (try? String(contentsOf: file, encoding: .utf16)) ?? ""
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/true"); return process
        })
        try importIO.write(["LeftCommandIsCtrl": .absent, "RightCommandIsCtrl": .string("N")], wrapper: wrapper)
        check(importText.contains("[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\DNF.exe\\Mac Driver]") && importText.contains("\"LeftCommandIsCtrl\"=-") && importText.contains("\"RightCommandIsCtrl\"=\"N\""), "registry import targets only owned DNF values with string and delete syntax")
        check(!importText.contains("D3DMETAL") && !importText.contains("never-return-this"), "registry import contains no renderer or unrelated registry data")
        try io.write(["D3DMETAL": .boolean(false), "CNC_DDRAW": .absent], wrapper: wrapper)
        let updated = try PropertyListSerialization.propertyList(from: Data(contentsOf: info), options: [], format: nil) as! [String: Any]
        check((updated["D3DMETAL"] as? NSNumber)?.boolValue == false && updated["CNC_DDRAW"] == nil && updated["D9VK"] as? Bool == true && updated["Unrelated"] as? String == "preserve", "renderer mutation preserves unrelated plist fields and removes originally absent keys")
    }
}
