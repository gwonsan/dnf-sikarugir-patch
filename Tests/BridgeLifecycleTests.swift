import AppKit
import Darwin

private final class PendingGameSettingsIO: GameSettingsIO {
    let support: URL
    let running: Bool
    var values:[String:GameSettingsValue] = [:]
    init(support:URL,running:Bool) { self.support = support; self.running = running }
    func isGameRunning(wrapper:URL) throws -> Bool { running }
    func read(wrapper:URL) throws -> GameSettingsSnapshot { GameSettingsSnapshot(values:values,globalValues:[:]) }
    func write(_ changes:[String:GameSettingsValue],wrapper:URL) throws {
        do { let lease = try PatchLock.acquire(directory:support,shared:true); lease.release(); throw PatchError(message:"fixture: pending writes require exclusive lease") }
        catch PatchLock.Failure.busy {}
        values.merge(changes) { _,new in new }
        try Data().write(to:support.appendingPathComponent("settings-applied"))
    }
}
@main struct BridgeLifecycleTests {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--scenario" {
            try scenario(args[1], root: URL(fileURLWithPath: args[2]))
            return
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DNF bridge lifecycle \(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var failures = 0
        for name in ["idle", "success", "multiple", "locked", "active", "error", "retry", "detached", "quit-active", "mixed", "pending", "pending-running"] {
            let directory = root.appendingPathComponent(name)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let log = directory.appendingPathComponent("output")
            fm.createFile(atPath: log.path, contents: nil)
            let output = try FileHandle(forWritingTo: log)
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--scenario", name, directory.path]
            child.standardOutput = output
            child.standardError = output
            try child.run()
            let deadline = Date().addingTimeInterval(6)
            while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            let timedOut = child.isRunning
            if timedOut { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
            try output.close()
            let prefix = directory.appendingPathComponent("DNF.app/Contents/SharedSupport/prefix")
            let completions = (try? String(contentsOf: prefix.appendingPathComponent("completed"), encoding: .utf8))?.split(separator: "\n").count ?? 0
            let expectedCompletions = ["success": 1, "multiple": 2, "active": 2, "retry": 1, "detached": 1, "quit-active": 2, "mixed": 1,"pending":1,"pending-running":1]
            let incomplete = expectedCompletions[name].map { completions != $0 } ?? false
            let lostError = ["error", "mixed"].contains(name) && !fm.fileExists(atPath: directory.appendingPathComponent("error-checked").path)
            var detachedSurvived = true
            if name == "detached" {
                let marker = prefix.appendingPathComponent("detached")
                let deadline = Date().addingTimeInterval(3)
                while !fm.fileExists(atPath: marker.path) && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
                detachedSurvived = fm.fileExists(atPath: marker.path)
            }
            if timedOut || child.terminationStatus != 0 || incomplete || lostError || !detachedSurvived {
                failures += 1
                print("FAIL: bridge \(name): \(timedOut ? "did not exit when idle" : "exit \(child.terminationStatus), completions=\(completions), lostError=\(lostError)")")
                print(try String(contentsOf: log, encoding: .utf8))
            } else {
                print("PASS: bridge \(name)")
            }
        }
        if failures > 0 { exit(1) }
    }

    static func scenario(_ name: String, root: URL) throws {
        let fm = FileManager.default
        let wrapper = root.appendingPathComponent("DNF.app")
        let prefix = wrapper.appendingPathComponent("Contents/SharedSupport/prefix")
        let plugin = prefix.appendingPathComponent("drive_c/Program Files (x86)/NeoplePlugin/NeopleCustomURLStarter.exe")
        let wine = wrapper.appendingPathComponent("Contents/SharedSupport/wine/bin/wine")
        try fm.createDirectory(at: plugin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: plugin)
        try Data("""
        #!/bin/sh
        echo started >> "$WINEPREFIX/started"
        case "$2" in
          neople://slow) /bin/sleep 2 ;;
          neople://fail) exit 7 ;;
          neople://detached) (/bin/sleep 2; echo alive > "$WINEPREFIX/detached") & ;;
        esac
        echo completed >> "$WINEPREFIX/completed"
        exit 0
        """.utf8).write(to: wine)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        let support = root.appendingPathComponent("Support")
        let settings = GameSettingsService(directory:support.appendingPathComponent("GameSettings"),io:PendingGameSettingsIO(support:support,running:name == "pending-running"))
        if name.hasPrefix("pending") { try settings.save(GameSettings(commandToControl:false,leftOptionIsAlt:true,rightOptionIsAlt:true,d3dMetal:true,cncDDraw:true),wrapper:wrapper) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var stateReads = 0
        let delegate = BridgeDelegate(support: support,settings:settings) {
            stateReads += 1
            return PatchState(wrapperPath: wrapper.path, previousHandler: nil, originalFonts: [:], installed: true)
        }
        app.delegate = delegate
        // Unbundled test executables do not reliably receive Launch Services startup
        // notifications in a sandbox. Deliver the delegate event explicitly.
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let url: (String) -> URL = { URL(string: "neople://" + $0)! }
        let check: (Bool, String) -> Void = { value, message in
            if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if name == "locked" {
                do {
                    try PatchLock.withLock(directory: support) {
                        delegate.application(app, open: [url("start")])
                        check(stateReads == 0, "web launch must not read mutable state while installation holds its lock")
                        check(!fm.fileExists(atPath: prefix.appendingPathComponent("started").path), "web launch must not start Wine during installation")
                        check(app.windows.contains { $0.isVisible }, "busy launch must give an actionable error")
                    }
                    exit(0)
                } catch { fputs("\(error)\n", stderr); exit(1) }
            }
            if name == "detached" { delegate.application(app, open: [url("detached")]) }
            if name == "success" || name.hasPrefix("pending") { delegate.application(app, open: [url("start")]) }
            if ["multiple", "active", "quit-active"].contains(name) {
                delegate.application(app, open: [url("start"), url("slow")])
            }
            if name == "mixed" {
                delegate.application(app, open: [URL(string: "invalid://request")!, url("start")])
            }
            if name == "error" || name == "retry" {
                delegate.application(app, open: [url("fail")])
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if name == "quit-active" { app.terminate(nil) }
            if name == "active" || name == "quit-active" {
                var entered = false
                do { try PatchLock.withLock(directory: support) { entered = true } } catch {}
                check(!entered, "an active Wine launch must block installation even after a second child has exited")
            }
            if name == "retry" {
                check(app.windows.contains { $0.isVisible }, "failed launch displays an error before retry")
                delegate.application(app, open: [url("start")])
                check(!app.windows.contains { $0.isVisible }, "successful retry closes stale errors")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if name == "error" || name == "mixed" {
                check(app.windows.contains { $0.isVisible }, "idle exit must not hide a launch error")
                do { try PatchLock.withLock(directory: support) {} } catch {
                    check(false, "failed launch must release its lock")
                }
                fm.createFile(atPath: root.appendingPathComponent("error-checked").path, contents: Data())
                exit(0)
            }
            if ["multiple", "active", "quit-active"].contains(name) {
                check(app.isRunning, "do not exit until every launch finishes")
            }
        }
        app.run()
        if name.hasPrefix("pending") {
            check(fm.fileExists(atPath:support.appendingPathComponent("settings-applied").path) == (name == "pending"),"only stopped-game pending settings apply before launch")
            check((try? settings.hasPending(wrapper:wrapper)) == (name == "pending-running"),"running game retains pending settings for next launch")
        }
        withExtendedLifetime(delegate) {}
    }
}
