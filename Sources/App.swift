import AppKit

final class BridgeDelegate: NSObject, NSApplicationDelegate {
    private var children: [Process] = []
    private var status: NSTextField?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        let actions = NSMenu()
        actions.addItem(withTitle: "던파 웹 실행 연결 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = actions
        menu.addItem(item)
        NSApp.mainMenu = menu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 140), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "던파 웹 실행 연결"
        window.isReleasedWhenClosed = false
        let status = NSTextField(wrappingLabelWithString: "던파 홈페이지에서 GAME START를 눌러 주세요.")
        status.frame = NSRect(x: 24, y: 24, width: 412, height: 90)
        window.contentView?.addSubview(status)
        self.status = status
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            do {
                let state = try Installer.readState()
                guard let process = makeLaunchProcess(request: url.absoluteString, wrapper: URL(fileURLWithPath: state.wrapperPath)) else {
                    throw PatchError(message: "실행 요청이 올바르지 않거나 Wine/네오플 플러그인을 찾을 수 없습니다.")
                }
                process.terminationHandler = { [weak self] child in
                    DispatchQueue.main.async {
                        self?.children.removeAll { $0 === child }
                        if child.terminationStatus != 0 {
                            self?.status?.stringValue = "Wine 실행 오류: 코드 \(child.terminationStatus). 패치 폴더의 진단.command를 실행해 주세요."
                        }
                    }
                }
                try process.run()
                children.append(process)
                status?.stringValue = "네오플 런처가 실행 요청을 처리 중입니다.\n다운로드 또는 게임 창을 확인해 주세요."
            } catch {
                let alert = NSAlert()
                alert.messageText = "던파 실행 연결 오류"
                alert.informativeText = "설치.command를 다시 실행해 주세요. " + error.localizedDescription
                alert.runModal()
            }
        }
    }
}

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
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
