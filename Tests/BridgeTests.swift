import AppKit

@main struct BridgeTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = BridgeDelegate()
        app.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        guard !app.windows.contains(where: { $0.isVisible }) else {
            fputs("FAIL: launching the bridge must not show an instruction window\n", stderr)
            exit(1)
        }
        print("PASS: bridge starts without an instruction window")
        delegate.application(app, open: [URL(string: "invalid://bridge-test")!])
        let visible = app.windows.filter { $0.isVisible }
        guard visible.count == 1, visible[0].title == "던파 실행 연결 오류",
              visible[0].contentView?.subviews.compactMap({ $0 as? NSTextField }).contains(where: { $0.stringValue.contains("설치.command") }) == true else {
            fputs("FAIL: a failed launch must display an actionable error\n", stderr)
            exit(1)
        }
        delegate.application(app, open: [URL(string: "invalid://second-bridge-test")!])
        guard app.windows.filter({ $0.isVisible }).count == 1 else {
            fputs("FAIL: repeated errors must reuse the error window\n", stderr)
            exit(1)
        }
        visible[0].close()
        print("PASS: failed launches show one actionable error window")
        withExtendedLifetime(delegate) {}
    }
}
