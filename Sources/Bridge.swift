import AppKit

final class BridgeDelegate: NSObject, NSApplicationDelegate {
    private let support: URL
    private let readState: () throws -> PatchState

    init(support: URL = Installer.support, readState: @escaping () throws -> PatchState = Installer.readState) {
        self.support = support
        self.readState = readState
        super.init()
    }

    private var children: [Process] = []
    private var terminationRequested = false
    private var idleExit: DispatchWorkItem?
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
        scheduleIdleExit()
    }

    private func scheduleIdleExit() {
        idleExit?.cancel()
        if terminationRequested, children.isEmpty {
            NSApp.terminate(nil)
            return
        }
        guard children.isEmpty, window?.isVisible != true else { return }
        // Allow Launch Services to deliver a URL arriving just after app startup.
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.children.isEmpty, self.window?.isVisible != true else { return }
            NSApp.terminate(nil)
        }
        idleExit = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: task)
    }

    private func showError(_ message: String) {
        idleExit?.cancel()
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { children.isEmpty }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !children.isEmpty else { return .terminateNow }
        // Keep the shared leases until every starter finishes, including on explicit Quit.
        terminationRequested = true
        // terminateLater enters a modal loop that can stall our main-queue completions.
        // Cancel this quit and request it again once the children have finished.
        return .terminateCancel
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        idleExit?.cancel()
        if !urls.isEmpty { window?.orderOut(nil) }
        for url in urls {
            do {
                // Shared leases permit multiple launches but exclude installation and restoration.
                let lease = try PatchLock.acquire(directory: support, shared: true)
                let state = try readState()
                guard let process = makeLaunchProcess(request: url.absoluteString, wrapper: URL(fileURLWithPath: state.wrapperPath)) else {
                    throw PatchError(message: "실행 요청이 올바르지 않거나 Wine/네오플 플러그인을 찾을 수 없습니다.")
                }
                process.terminationHandler = { [weak self] child in
                    DispatchQueue.main.async {
                        lease.release()
                        self?.children.removeAll { $0 === child }
                        if child.terminationStatus != 0 {
                            self?.showError("Wine 실행 오류: 코드 \(child.terminationStatus). 패치 폴더의 진단.command를 실행해 주세요.")
                        }
                        self?.scheduleIdleExit()
                    }
                }
                // Keyboard capture never blocks website launch if permission or profile is unavailable.
                try? KeyboardService.startIfEnabled(wrapper: URL(fileURLWithPath:state.wrapperPath))
                try process.run()
                children.append(process)
            } catch PatchLock.Failure.busy {
                showError("설치 또는 복원 작업 중입니다. 작업이 끝난 뒤 홈페이지에서 GAME START를 다시 눌러 주세요.")
            } catch {
                showError("설치.command를 다시 실행해 주세요. " + error.localizedDescription)
            }
        }
        scheduleIdleExit()
    }
}

