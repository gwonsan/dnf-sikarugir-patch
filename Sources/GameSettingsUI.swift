import Foundation

/// Explicit switches keep Wine's key interpretation distinct from physical key remapping.
final class GameSettingsEditor {
    private let wrapper: URL
    private let service: GameSettingsService
    private let lockDirectory: URL
    init(wrapper:URL,service:GameSettingsService,lockDirectory:URL) {
        self.wrapper = wrapper; self.service = service; self.lockDirectory = lockDirectory
    }
    func run(terminal:MenuTerminal) throws {
        var settings = try service.read(wrapper:wrapper), saved = settings
        var selected = 0, note = "S 저장 · P 저장한 설정 적용 · R 원래 설정 복원", previous = ""
        let labels = ["Command를 Control로 입력","왼쪽 Option을 Alt로 입력","오른쪽 Option을 Alt로 입력","D3DMetal","CNC-DDraw"]
        func flags(_ s:GameSettings) -> [Bool] { [s.commandToControl,s.leftOptionIsAlt,s.rightOptionIsAlt,s.d3dMetal,s.cncDDraw] }
        while !terminal.wantsExit {
            let width = max(20,terminal.size.width-4)
            let values = flags(settings)
            let rows = labels.enumerated().map { "\($0.offset == selected ? "›" : " ") \($0.offset+1)  \($0.element)   \(values[$0.offset] ? "켜짐" : "꺼짐")" }
            let explanation = ["Command → Control을 끄면", "물리 Control은 Control로 유지됩니다.", "Command의 출력은 Wine이 결정합니다.", "", "키 자체를 바꾸려면 메인 메뉴 5", "키보드 매핑을 사용하세요.", "", "Wine·그래픽 설정은 재실행 후 반영", "게임 실행 중에는 적용을 미룹니다."]
            var body: [String]
            if width >= 68 {
                let left = max(30,width/2-2)
                body = (0..<max(rows.count,explanation.count)).map { TerminalText.pad($0 < rows.count ? rows[$0] : "",left) + " │ " + TerminalText.fit($0 < explanation.count ? explanation[$0] : "",width-left-3) }
            } else { body = rows + ["", "Wine·그래픽 변경은 게임 재실행 필요"] }
            let lines = ["DNF   /   게임 설정\(settings != saved ? " · 변경됨" : "")",String(repeating:"━",count:width),""] + body + ["",service.status(wrapper:wrapper),TerminalText.fit(note,width),"↑↓ 선택  Enter / 숫자 전환  S 저장  P 적용  R 복원","Esc 저장하지 않고 뒤로   Q 종료"]
            let frame = "\(terminal.size)" + lines.joined(separator:"\n")
            if frame != previous || !terminal.rich { terminal.draw(lines); previous = frame }
            let key = terminal.key()
            var toggle: Int?
            switch key {
            case .up: selected = max(0,selected-1)
            case .down: selected = min(4,selected+1)
            case .enter: toggle = selected
            case .number(let index): if index < 5 { selected = index; toggle = index }
            case .save:
                do { try PatchLock.withLock(directory:lockDirectory) { try service.save(settings,wrapper:wrapper) }; saved = settings
                    note = "게임 설정 저장됨 · P 적용 또는 다음 게임 실행 시 반영"
                } catch { note = error.localizedDescription }
            case .permissions:
                do {
                    terminal.draw(["DNF   /   게임 설정","","저장한 설정 적용 중… 게임이 실행 중이면 다음 실행 전까지 대기합니다."])
                    let applied = try PatchLock.withLock(directory:lockDirectory) { try service.applyPending(wrapper:wrapper) }
                    note = applied ? "게임 설정 적용 완료 · 게임을 새로 실행해 주세요." : "게임 실행 중 · 종료 후 P를 누르거나 다음 실행 때 적용"
                } catch { note = "적용 오류: " + error.localizedDescription }
                previous = ""
            case .retry:
                if confirm(terminal) {
                    do { let restored = try PatchLock.withLock(directory:lockDirectory) { try service.restore(wrapper:wrapper) }
                        if restored { settings = try service.read(wrapper:wrapper); saved = settings; note = "게임 설정 복원 완료" }
                        else { note = "게임 실행 중 · 게임을 종료한 뒤 R 복원을 다시 눌러 주세요." }
                    } catch { note = "복원 오류: " + error.localizedDescription }
                }
                previous = ""
            case .back: return
            case .quit: terminal.requestExit(); return
            default: break
            }
            if let toggle {
                switch toggle {
                case 0: settings.commandToControl.toggle()
                case 1: settings.leftOptionIsAlt.toggle()
                case 2: settings.rightOptionIsAlt.toggle()
                case 3: settings.d3dMetal.toggle()
                default: settings.cncDDraw.toggle()
                }
                note = "변경됨 · S 저장 전에는 적용되지 않습니다."
            }
        }
    }
    private func confirm(_ terminal:MenuTerminal) -> Bool {
        terminal.draw(["DNF   /   게임 설정 복원","","TUI에서 적용한 Wine·그래픽 값을 복원합니다.","사용자가 나중에 직접 바꾼 값은 유지합니다.","키 매핑은 메인 메뉴 5에서 별도로 끌 수 있습니다.","","[1] 취소   [2] 복원 진행"])
        while !terminal.wantsExit {
            switch terminal.key() {
            case .number(1): return true
            case .number(0),.enter,.back: return false
            case .quit: terminal.requestExit(); return false
            default: break
            }
        }
        return false
    }
}
