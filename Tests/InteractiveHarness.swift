import Foundation
import Darwin

@main struct InteractiveHarness {
    static func main() {
        let args = CommandLine.arguments
        do {
            let status = try InteractiveCommand.run(URL(fileURLWithPath: args[1]), arguments: Array(args.dropFirst(2)))
            guard tcgetpgrp(STDIN_FILENO) == getpgrp() else {
                fputs("parent did not regain the terminal\n", stderr); exit(90)
            }
            print("INTERACTIVE_STATUS=\(status)")
        } catch {
            guard tcgetpgrp(STDIN_FILENO) == getpgrp() || isatty(STDIN_FILENO) == 0 else { exit(90) }
            fputs("INTERACTIVE_ERROR=\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
