import Foundation
import Darwin

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct TerminalTests {
    static func main() throws {
        setlocale(LC_CTYPE, "en_US.UTF-8")
        expect(TerminalUI.normal.contains(.keyboard), "key mapping is reachable in normal menu")
        expect(TerminalKey.decode([115]) == .save && TerminalKey.decode([100]) == .delete, "keyboard editor shortcuts decode")
        let root = URL(fileURLWithPath: "/tmp/Package With Spaces")
        var snapshot = MenuSnapshot()
        snapshot.readySource = true
        let fresh = try MenuAction.install.arguments(snapshot: snapshot, root: root)
        expect(fresh == ["--install-ready", "/tmp/Package With Spaces/설치 자료/DNF.app"], "ready assets route to the ready installer as one argument")
        snapshot.wrapperPath = "/tmp/My Game.app"
        snapshot.wrapperExists = true
        snapshot.wineAvailable = true
        snapshot.recorded = true
        snapshot.prepared = true
        snapshot.readySource = false
        let reinstall = try MenuAction.install.arguments(snapshot: snapshot, root: root)
        expect(reinstall == ["--install-ready", "/tmp/Package With Spaces/설치 자료/DNF.app", "/tmp/My Game.app"], "reuse a recorded ready app after downloaded source cleanup")
        snapshot.recorded = false
        let restored = try MenuAction.install.arguments(snapshot: snapshot, root: root)
        expect(restored == ["--install", "/tmp/My Game.app"], "reapply restored ready app after source cleanup without needing a fresh ZIP")
        snapshot.recorded = true
        snapshot.prepared = false
        let patch = try MenuAction.install.arguments(snapshot: snapshot, root: root)
        expect(patch == ["--install", "/tmp/My Game.app"], "custom existing wrappers use the existing patch path")
        snapshot.wrapperExists = false
        do { _ = try MenuAction.install.arguments(snapshot: snapshot, root: root); expect(false, "missing recorded app must require recovery") } catch {}
        snapshot.stateProblem = "unreadable state"
        do { _ = try MenuAction.install.arguments(snapshot: snapshot, root: root); expect(false, "unreadable installation state must not be ignored") } catch {}
        let reset = try MenuAction.connectionOnly.arguments(snapshot: snapshot, root: root)
        expect(reset == ["--uninstall", "--connection-only"], "connection-only uses the explicit recovery flag")
        let explicit = try MenuAction.selectApp.arguments(snapshot: snapshot, root: root)
        expect(explicit == ["--install-select"], "explicit app selection cannot auto-select a detected wrapper")
        let fromScratch = try MenuAction.install.arguments(snapshot: MenuSnapshot(), root: root)
        expect(fromScratch == ["--setup"], "packages without ready assets can create a wrapper")
        expect(TerminalText.width("한글 AB") == 7, "Korean terminal cells count as two")
        expect(TerminalText.width("e\u{301}") == 1, "combining marks do not shift alignment")
        expect(TerminalText.width(TerminalText.fit("가나다라마바사", 8)) <= 8, "truncate at terminal cell boundaries")
        let unsafe = "\u{1b}[2Jsecret neople://private-token\u{7}"
        let safe = TerminalText.clean(unsafe)
        expect(!safe.contains("\u{1b}") && !safe.contains("private-token"), "logs cannot inject terminal controls or reveal authentication URLs")
        snapshot = MenuSnapshot(); snapshot.wrapperPath = "/tmp/아주 긴 설치 폴더/My Game.app"; snapshot.recorded = true
        for width in [28, 40, 76, 100] {
            let lines = TerminalUI.menuLines(snapshot: snapshot, selected: 0, advanced: false, width: width)
            expect(lines.allSatisfy { TerminalText.width($0) <= width }, "all menu rows fit at width \(width)")
            expect(lines.contains { $0.contains("설치") }, "installation is visible at width \(width)")
        }
        expect(TerminalKey.decode([27,91,65]) == .up && TerminalKey.decode([27,79,66]) == .down, "both arrow sequence styles work")
        expect(TerminalKey.decode([3]) == .quit && TerminalKey.decode([13]) == .enter, "quit and enter keys")
        let log = MenuLog()
        log.append(Data("앞부분 ".utf8))
        log.append(Data("완료\n오류: neople://secret\n".utf8))
        expect(log.lines.first == "앞부분 완료" && !log.lines.joined().contains("secret"), "split UTF-8 output assembles and redacts before display")
        for _ in 0..<1000 { log.append(Data((String(repeating: "x", count: 200) + "\n").utf8)) }
        expect(log.lines.count <= 80, "logs stay bounded")
        print("PASS: install routing, recovery guardrails, Korean cell widths, key decoding and safe bounded logs")
    }
}
