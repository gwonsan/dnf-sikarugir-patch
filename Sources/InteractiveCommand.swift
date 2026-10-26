import Foundation
import Darwin

/// Give an interactive installer its own foreground process group. Foundation's
/// Process creates a new group without handing it the TTY, so stdin stops it.
enum InteractiveCommand {
    static func run(_ executable: URL, arguments: [String]) throws -> Int32 {
        let foreground = tcgetpgrp(STDIN_FILENO)
        guard foreground >= 0, foreground == getpgrp() else {
            throw PatchError(message: "Rosetta 설치는 앞에 열린 대화형 터미널에서 실행해 주세요.")
        }
        var attributes: posix_spawnattr_t?
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_START_SUSPENDED | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        try check(posix_spawnattr_setflags(&attributes, Int16(flags)))
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for number in [SIGINT, SIGQUIT, SIGTERM, SIGHUP, SIGTSTP, SIGTTIN, SIGTTOU] { sigaddset(&defaults, number) }
        try check(posix_spawnattr_setsigdefault(&attributes, &defaults))
        var empty = sigset_t()
        sigemptyset(&empty)
        try check(posix_spawnattr_setsigmask(&attributes, &empty))

        // tcsetpgrp must also work when the parent takes ownership back from
        // the child. Block SIGTTOU only on this thread and restore its mask.
        var blocked = sigset_t(), previousMask = sigset_t()
        sigemptyset(&blocked); sigaddset(&blocked, SIGTTOU)
        try check(pthread_sigmask(SIG_BLOCK, &blocked, &previousMask))
        defer { pthread_sigmask(SIG_SETMASK, &previousMask, nil) }

        let strings = ([executable.path] + arguments).map { strdup($0) }
        defer { for pointer in strings { free(pointer) } }
        var argv = strings + [nil]
        var child: pid_t = 0
        let result = argv.withUnsafeMutableBufferPointer {
            posix_spawn(&child, executable.path, nil, &attributes, $0.baseAddress!, environ)
        }
        try check(result)
        var reaped = false
        defer {
            if !reaped {
                // The leader may have forked helpers in this group. We still
                // own the unreaped leader, so the group ID cannot be reused.
                kill(-child, SIGKILL)
                var status: Int32 = 0
                while waitpid(child, &status, 0) == -1 && errno == EINTR {}
            }
            // Always return input ownership before the TUI restores raw mode.
            _ = tcsetpgrp(STDIN_FILENO, foreground)
        }
        // START_SUSPENDED prevents the child reading stdin before this handoff.
        guard tcsetpgrp(STDIN_FILENO, child) == 0 else { try check(errno); return 1 }
        guard kill(child, SIGCONT) == 0 else { try check(errno); return 1 }
        var status: Int32 = 0
        while true {
            let waited = waitpid(child, &status, WUNTRACED)
            if waited == -1 {
                if errno == EINTR { continue }
                try check(errno)
            }
            if status & 0xff == 0x7f {
                // Ctrl-Z or an unexpected input stop must not leave the TUI
                // waiting forever for a suspended installer.
                throw PatchError(message: "Rosetta 설치가 일시중지되어 취소했습니다. 다시 설치해 주세요.")
            }
            reaped = true
            if status & 0x7f == 0 { return (status >> 8) & 0xff }
            return 128 + (status & 0x7f)
        }
    }

    private static func check(_ status: Int32) throws {
        guard status == 0 else {
            throw PatchError(message: "대화형 설치 실행 실패: \(String(cString: strerror(status)))")
        }
    }
}
