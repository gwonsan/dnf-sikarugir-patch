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
    }

    private func showError(_ message: String) {
        if let window, let status {
            status.stringValue = message
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 140), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "던파 실행 연결 오류"
        window.isReleasedWhenClosed = false
        let status = NSTextField(wrappingLabelWithString: message)
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
                            self?.showError("Wine 실행 오류: 코드 \(child.terminationStatus). 패치 폴더의 진단.command를 실행해 주세요.")
                        }
                    }
                }
                try process.run()
                children.append(process)
            } catch {
                showError("설치.command를 다시 실행해 주세요. " + error.localizedDescription)
            }
        }
    }
}

