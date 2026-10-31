import Foundation
import Darwin

@main struct TerminalSessionTests {
    static func main() throws {
        // Compile the production AppleScript without executing any UI action.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DNF close syntax " + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("close.applescript")
        try TerminalSession.closeScript.write(to: script, atomically: true, encoding: .utf8)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        compiler.arguments = ["-o", root.appendingPathComponent("close.scpt").path, script.path]
        try compiler.run(); compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else { fatalError("Terminal close script does not compile") }
        // Invalid targets must return before detaching or contacting Terminal.
        setenv("TERM_PROGRAM", "Apple_Terminal", 1)
        let originalSession = getsid(0)
        for tty in ["", "/dev/console", "/dev/ttys001\n", "\"; quit", "/dev/ttys1/../x"] {
            try TerminalSession.closeCompletedWindow(tty: tty)
            precondition(getsid(0) == originalSession, "Invalid TTY must not start a detached watcher")
        }
        setenv("TERM_PROGRAM", "Other", 1)
        try TerminalSession.closeCompletedWindow(tty: "/dev/ttys001")
        print("PASS: close script compiles; invalid targets and other terminals do nothing (no UI execution)")
    }
}
