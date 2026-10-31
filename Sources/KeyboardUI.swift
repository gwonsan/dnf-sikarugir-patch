import AppKit

/// The editor uses explicit key lists: Terminal need not capture OS modifier shortcuts.
final class KeyboardEditor {
    private let wrapper: URL
    private let store: KeyProfileStore
    private let activate: (URL) throws -> Void
    private var profile: KeyProfile
    private var saved: KeyProfile
    private var selected = 0
    private var note = "S 저장 · Esc 저장하지 않고 돌아가기"

    init(wrapper: URL, store: KeyProfileStore, activate: @escaping (URL) throws -> Void) throws {
        self.wrapper = wrapper; self.store = store; self.activate = activate
        profile = try store.load(wrapper: wrapper); saved = profile
    }
    private func columns(left: [String], right: [String], width: Int) -> [String] {
        guard width >= 68 else { return left + [""] + right.prefix(4) }
        let a = max(30, width / 2 - 2), b = width - a - 3
        return (0..<max(left.count,right.count)).map {
            TerminalText.pad($0 < left.count ? left[$0] : "", a) + " │ " + TerminalText.fit($0 < right.count ? right[$0] : "", b)
        }
    }
    func run(terminal: MenuTerminal) throws {
        var lastFrame = ""
        while !terminal.wantsExit {
            let size = terminal.size, width = max(20, size.width - 4)
            let visible = max(3, size.height - 14)
            selected = min(selected, max(0,profile.bindings.count - 1))
            let first = max(0,min(selected-visible/2,max(0,profile.bindings.count-visible)))
            let rows = profile.bindings.enumerated().dropFirst(first).prefix(visible).map { index,binding in
                "\(index == selected ? "›" : " ") \(KeyCatalog.name(binding.source)) → \(binding.target.label) [\(profile.backend == .native ? "자체" : "K → 던파")]"
            }
            var left = ["내 키 매핑  \(profile.enabled ? "켜짐" : "꺼짐")\(profile != saved ? " · 변경됨" : "")", ""]
            left += rows.isEmpty ? ["아직 매핑이 없습니다.", "A 추가 또는 R 한/영 프리셋"] : rows
            let status = profile.enabled ? KeyboardService.status(wrapper:wrapper) : "비활성 · 기본 키 입력 사용"
            let right = ["던파 안에서만 적용", "", "처리 방식: \(profile.backend.label)", KarabinerRuntime.detection,
                         "", "Karabiner 연결 성공 시", "Karabiner 변환 → 던파 전용 전달", "", "실제 상태", status,
                         "", "Command·Option 해석과 그래픽은", "메인 메뉴 6 게임 설정에서 변경", "Caps·한영·반복은 전용 보정기로 완료"]
            var lines = ["DNF   /   키보드 매핑", String(repeating: "━", count: width), ""]
            lines += columns(left: left, right: width >= 68 ? right : [right[0],"처리 방식: " + profile.backend.label,"상태: " + status], width: width)
            lines += ["", TerminalText.fit(note,width), "↑↓ 선택  Enter 변경  A 추가  D 삭제  R 프리셋", "1 켜기/끄기  2 초기화  3 처리 방식  S 저장  P 권한"]
            let frame = "\(size)" + lines.joined(separator:"\n")
            if frame != lastFrame || !terminal.rich { terminal.draw(lines); lastFrame = frame }
            let key = terminal.key()
            if key == .advanced || key == .enter { lastFrame = "" }
            switch key {
            case .up: selected = max(0,selected-1)
            case .down: selected = min(max(0,profile.bindings.count-1),selected+1)
            case .advanced:
                if let source = pickSource(terminal), let target = pickTarget(terminal) {
                    profile.bindings.removeAll { $0.source == source }; profile.bindings.append(.init(source:source,target:target))
                    selected = profile.bindings.count-1; note = "매핑 추가됨 · S를 눌러 저장하세요."
                }
            case .enter:
                if !profile.bindings.isEmpty, let target = pickTarget(terminal) { profile.bindings[selected].target = target; note = "매핑 변경됨 · S 저장" }
            case .delete:
                if !profile.bindings.isEmpty { profile.bindings.remove(at:selected); note = "매핑 삭제됨 · S 저장" }
            case .retry: profile.useKoreanPreset(); note = "한/영·Caps Lock 프리셋 불러옴 · 1로 켠 뒤 S 저장"
            case .number(0): profile.enabled.toggle()
            case .number(1): profile.bindings.removeAll(); profile.enabled = false; note = "초기화 준비됨 · S 저장 전까지 기존 설정 유지"
            case .number(2):
                let all = KeyboardBackend.allCases
                profile.backend = all[(all.firstIndex(of:profile.backend)!+1)%all.count]
                note = "처리 방식 변경됨 · S 저장"
            case .save:
                do {
                    try store.save(profile); saved = profile
                    if profile.enabled { try activate(wrapper) }
                    note = "키 매핑 저장됨 · 적용 상태는 오른쪽에서 확인하세요."
                } catch { note = "저장/시작 오류: \(error.localizedDescription)" }
            case .permissions:
                do { try KeyboardService.openPermissionRequest(wrapper:wrapper)
                    note = "DNF Keyboard의 입력 모니터링·손쉬운 사용 허용 후 S 저장"
                } catch { note = error.localizedDescription }
            case .back: return
            case .quit: terminal.requestExit(); return
            default: break
            }
        }
    }
    private func pickSource(_ terminal: MenuTerminal) -> UInt16? {
        pick(title:"바꿀 입력 키", labels:KeyCatalog.keys.map(\.name), terminal:terminal).map { KeyCatalog.keys[$0].code }
    }
    private func pickTarget(_ terminal: MenuTerminal) -> KeyTarget? {
        let targets: [KeyTarget] = [.toggleInputSource,.disabled] + KeyCatalog.keys.map { .key($0.code) }
        return pick(title:"게임에 보낼 키", labels:targets.map(\.label), terminal:terminal).map { targets[$0] }
    }
    private func pick(title: String, labels: [String], terminal: MenuTerminal) -> Int? {
        var selected = 0, lastFrame = ""
        while !terminal.wantsExit {
            let size = terminal.size, width = max(20,size.width-4), visible = max(3,size.height-9)
            let first = max(0,min(selected-visible/2,max(0,labels.count-visible)))
            let lines = ["DNF   /   \(title)", String(repeating:"━",count:width), ""] +
                labels.enumerated().dropFirst(first).prefix(visible).map { "\($0.offset == selected ? "›" : " ") \($0.element)" } +
                ["", "\(selected+1) / \(labels.count)   ↑↓ / J·K 이동   [ ] 페이지", "Enter 선택   Esc 취소   Q 종료"]
            let frame = "\(size)" + lines.joined(separator:"\n")
            if frame != lastFrame || !terminal.rich { terminal.draw(lines); lastFrame = frame }
            switch terminal.key() {
            case .up: selected = (selected+labels.count-1)%labels.count
            case .down: selected = (selected+1)%labels.count
            case .nextPage: selected = min(labels.count-1,selected+visible)
            case .previousPage: selected = max(0,selected-visible)
            case .enter: return selected
            case .back: return nil
            case .quit: terminal.requestExit(); return nil
            default: break
            }
        }
        return nil
    }
}
