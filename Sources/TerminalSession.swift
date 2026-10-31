import AppKit
import Darwin

/// A detached watcher closes only an empty, single-tab Terminal window with the
/// exact TTY that ran our command. An existing interactive shell stays open.
enum TerminalSession {
    static func closeCompletedWindow(tty: String) throws {
        guard ProcessInfo.processInfo.environment["TERM_PROGRAM"] == "Apple_Terminal",
              tty.range(of: "^/dev/ttys[0-9]+\\z", options: .regularExpression) != nil else { return }
        // Do not remain a process belonging to the terminal being observed.
        guard setsid() != -1 else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", closeScript, tty]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Permission denial, a reused TTY, or unsupported Terminal behavior is
        // harmless: leave the window open and never change global preferences.
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if process.isRunning { process.terminate() }
    }

    static let closeScript = """
    on run argv
        set targetTTY to item 1 of argv
        repeat 40 times
            if application "Terminal" is not running then return
            tell application "Terminal"
                set matchingWindow to missing value
                repeat with candidate in windows
                    repeat with candidateTab in tabs of candidate
                        if tty of candidateTab is targetTTY then
                            -- Never close another tab or an interactive shell.
                            if (count of tabs of candidate) is not 1 then return
                            set matchingWindow to candidate
                            if not busy of candidateTab and (count of processes of candidateTab) is 0 then
                                close matchingWindow
                                return
                            end if
                        end if
                    end repeat
                end repeat
                if matchingWindow is missing value then return
            end tell
            delay 0.2
        end repeat
    end run
    """
}
