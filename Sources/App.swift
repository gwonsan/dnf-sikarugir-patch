import AppKit

@main struct PatchApp {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if let command = args.first, command.hasPrefix("--") {
            do {
                switch command {
                case "--prepare-ready", "--install-ready":
                    guard args.count > 1 else { throw PatchError(message: "동봉한 DNF.app 경로를 지정하세요.") }
                    let source = URL(fileURLWithPath: args[1]).standardizedFileURL
                    let wrapper = args.count > 2 ? URL(fileURLWithPath: args[2]).standardizedFileURL : Installer.fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Sikarugir/DNF.app")
                    try PatchLock.withLock(directory: Installer.support) {
                        if command == "--prepare-ready" { try Prepared.prepare(source, wrapper: wrapper) }
                        else { try Prepared.install(source, wrapper: wrapper) }
                    }
                case "--setup", "--create-wrapper":
                    let wrapper = args.count > 1 ? URL(fileURLWithPath: args[1]).standardizedFileURL : Installer.fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Sikarugir/DNF.app")
                    try PatchLock.withLock(directory: Installer.support) {
                        if command == "--create-wrapper" { try Bootstrap.createWrapper(wrapper) }
                        else { try Bootstrap.setup(wrapper, installer: args.count > 2 ? args[2] : nil) }
                    }
                case "--install":
                    let wrapper = try Installer.chooseWrapper(args.count > 1 ? args[1] : nil)
                    try PatchLock.withLock(directory: Installer.support) { try Installer.install(wrapper) }
                case "--uninstall":
                    try PatchLock.withLock(directory: Installer.support) { try Installer.uninstall() }
                case "--diagnose":
                    let wrapper = args.count > 1 ? URL(fileURLWithPath: args[1]) : URL(fileURLWithPath: try Installer.readState().wrapperPath)
                    try Installer.diagnose(wrapper)
                default: throw PatchError(message: "사용법: --install-ready 동봉한앱 [설치경로] | --prepare-ready 동봉한앱 설치경로 | --setup [새 DNF.app 경로] [NeopleCustomURLBuilder.exe] | --create-wrapper [새 DNF.app 경로] | --install [DNF.app 경로] | --uninstall | --diagnose [DNF.app 경로]")
                }
            } catch {
                fputs("오류: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        let app = NSApplication.shared
        let delegate = BridgeDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
