import AppKit
import Darwin

struct MenuSnapshot {
    var wrapperPath: String?
    var recorded = false
    var wrapperExists = false
    var wineAvailable = false
    var prepared = false
    var readySource = false
    var connected = false
    var rosetta = true
    var appleSilicon = false
    var metal = false
    var stateProblem: String?

    static func capture(root: URL) -> MenuSnapshot {
        var result = MenuSnapshot()
        let fm = FileManager.default
        result.readySource = fm.fileExists(atPath: root.appendingPathComponent("설치 자료/DNF.app").path)
        if fm.fileExists(atPath: Installer.stateFile.path) {
            result.recorded = true
            do { result.wrapperPath = try Installer.readState().wrapperPath }
            catch { result.stateProblem = "설치 기록을 읽지 못했습니다. 기존 백업을 확인해 주세요." }
        } else {
            let candidates = ["Applications/Sikarugir/DNF.app", "Applications/DNF.app"].map { fm.homeDirectoryForCurrentUser.appendingPathComponent($0) }
            result.wrapperPath = candidates.first { makeLaunchProcess(request: "neople://patch-check", wrapper: $0) != nil }?.path
        }
        if let path = result.wrapperPath {
            let wrapper = URL(fileURLWithPath: path)
            result.wrapperExists = fm.fileExists(atPath: path)
            result.wineAvailable = makeLaunchProcess(request: "neople://patch-check", wrapper: wrapper) != nil
            let info = NSDictionary(contentsOf: wrapper.appendingPathComponent("Contents/Info.plist"))
            result.prepared = info?["DNFReadyVersion"] as? String == "1"
            result.metal = (info?["D3DMETAL"] as? NSNumber)?.boolValue == true
        }
        result.connected = Installer.handler() == patchBundleID
        var arm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0) == 0 { result.appleSilicon = arm == 1 }
        if result.appleSilicon {
            result.rosetta = (try? Installer.run(URL(fileURLWithPath: "/usr/bin/arch"), ["-x86_64", "/usr/bin/true"])) == 0
        }
        return result
    }

    var installationLabel: String {
        if stateProblem != nil { return "설치 기록 확인 필요" }
        if recorded && !wrapperExists { return "기존 앱을 찾을 수 없음" }
        if wineAvailable { return "설치됨" }
        return "설치 준비 필요"
    }
}

enum MenuAction: String {
    case install, diagnose, restore, homepage, keyboard, selectApp, setup, connectionOnly
    var title: String {
        switch self {
        case .install: return "설치 / 패치 다시 적용"
        case .diagnose: return "실행 문제 진단"
        case .restore: return "패치 복원"
        case .homepage: return "던파 홈페이지 열기"
        case .keyboard: return "키보드 매핑"
        case .selectApp: return "기존 DNF.app 선택"
        case .setup: return "빈 앱부터 새로 설치"
        case .connectionOnly: return "연결과 설치 기록만 정리"
        }
    }
    var detail: String {
        switch self {
        case .install: return "처음 설치하거나 현재 설정을 복구합니다."
        case .diagnose: return "Wine, 한글 설정과 웹 연결을 확인합니다."
        case .restore: return "원래 폰트 설정과 웹 연결을 복원합니다."
        case .homepage: return "로그인 후 GAME START를 눌러 주세요."
        case .keyboard: return "던파 안에서 사용할 키를 자유롭게 지정합니다."
        case .selectApp: return "직접 선택한 기존 앱에 패치를 적용합니다."
        case .setup: return "공식 자료로 앱을 만들고 플러그인을 설치합니다."
        case .connectionOnly: return "폰트 복원 없이 기록을 백업하고 정리합니다."
        }
    }
    var installs: Bool { [.install, .setup, .selectApp].contains(self) }
    func arguments(snapshot: MenuSnapshot, root: URL) throws -> [String] {
        switch self {
        case .install:
            if let problem = snapshot.stateProblem { throw PatchError(message: problem) }
            if snapshot.recorded && !snapshot.wrapperExists {
                throw PatchError(message: "기록된 DNF.app을 찾을 수 없습니다. 메뉴의 ‘패치 복원’으로 기존 기록을 정리한 뒤 다시 설치하세요.")
            }
            let source = root.appendingPathComponent("설치 자료/DNF.app").path
            if let wrapper = snapshot.wrapperPath {
                let needsReady = snapshot.prepared && (snapshot.recorded || snapshot.readySource || !snapshot.wineAvailable)
                return needsReady ? ["--install-ready", source, wrapper] : ["--install", wrapper]
            }
            return snapshot.readySource ? ["--install-ready", source] : ["--setup"]
        case .diagnose:
            guard let wrapper = snapshot.wrapperPath else { throw PatchError(message: "진단할 설치를 찾지 못했습니다. 먼저 설치하거나 고급 설정에서 기존 앱을 선택하세요.") }
            return ["--diagnose", wrapper]
        case .restore: return ["--uninstall"]
        case .connectionOnly: return ["--uninstall", "--connection-only"]
        case .selectApp: return ["--install-select"]
        case .setup: return ["--setup"]
        case .homepage, .keyboard: return []
        }
    }
}

enum TerminalText {
    static func clean(_ value: String) -> String {
        var text = value.replacingOccurrences(of: "\u{1b}\\][^\u{7}\u{1b}]*(?:\u{7}|\u{1b}\\\\)", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\u{1b}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "neople://[^\\s]+", with: "[인증 URL 숨김]", options: [.regularExpression, .caseInsensitive])
        return String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
    }
    static func width(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { total, scalar in
            let cells = wcwidth(Int32(scalar.value))
            return total + (cells >= 0 ? Int(cells) : (scalar.value >= 0x2e80 ? 2 : 1))
        }
    }
    static func fit(_ raw: String, _ cells: Int) -> String {
        let text = clean(raw)
        guard cells > 0 else { return "" }
        if width(text) <= cells { return text }
        var output = ""
        for character in text {
            if width(output + String(character)) > cells - 1 { break }
            output.append(character)
        }
        return output + "…"
    }
    static func pad(_ raw: String, _ cells: Int) -> String {
        let text = fit(raw, cells)
        return text + String(repeating: " ", count: max(0, cells - width(text)))
    }
}

enum TerminalKey: Equatable {
    case up, down, enter, back, quit, advanced, logs, retry, save, delete, permissions, nextPage, previousPage, number(Int), other
    static func decode(_ bytes: [UInt8]) -> TerminalKey {
        if bytes == [27,91,65] || bytes == [27,79,65] { return .up }
        if bytes == [27,91,66] || bytes == [27,79,66] { return .down }
        guard bytes.count == 1, let first = bytes.first else { return .other }
        switch first {
        case 10,13: return .enter
        case 27: return .back
        case 3,4,81,113: return .quit
        case 65,97: return .advanced
        case 76,108: return .logs
        case 82,114: return .retry
        case 83,115: return .save
        case 68,100: return .delete
        case 80,112: return .permissions
        case 74,106: return .down
        case 75,107: return .up
        case 93: return .nextPage
        case 91: return .previousPage
        case 49...57: return .number(Int(first - 49))
        default: return .other
        }
    }
}

final class MenuLog {
    private var pending = Data()
    private(set) var lines: [String] = []
    func append(_ data: Data, final: Bool = false) {
        pending.append(data)
        while let index = pending.firstIndex(of: 10) {
            add(String(decoding: pending[..<index], as: UTF8.self))
            pending.removeSubrange(...index)
        }
        if pending.count > 16384 { pending = pending.suffix(16384) }
        if final && !pending.isEmpty { add(String(decoding: pending, as: UTF8.self)); pending.removeAll() }
    }
    private func add(_ line: String) {
        let safe = TerminalText.fit(line, 1000)
        if !safe.isEmpty { lines.append(safe) }
        if lines.count > 80 { lines.removeFirst(lines.count - 80) }
    }
}

private final class MenuJob {
    let process = Process()
    let output = Pipe()
    let log = MenuLog()
    let started = Date()
    init(helper: URL, arguments: [String]) throws {
        process.executableURL = helper
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        var environment = ProcessInfo.processInfo.environment
        environment["NSUnbufferedIO"] = "YES"
        process.environment = environment
        let descriptor = output.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        try process.run()
        try? output.fileHandleForWriting.close()
    }
    func collect() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        // Bound each tick so noisy output cannot starve keyboard handling.
        for _ in 0..<64 {
            let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
            if count <= 0 { break }
            log.append(Data(buffer.prefix(count)))
        }
    }
    deinit { try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close() }
}

final class MenuTerminal {
    private var original = termios()
    private var active = false
    private var queued: [UInt8] = []
    private var stop = false
    private let mutex = NSLock()
    private var signals: [DispatchSourceSignal] = []
    private var oldSignals: [(Int32, sig_t?)] = []
    let rich: Bool
    let color: Bool
    var wantsExit: Bool { mutex.lock(); defer { mutex.unlock() }; return stop }
    init() {
        rich = ProcessInfo.processInfo.environment["TERM"] != "dumb"
        color = rich && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
    }
    func requestExit() { mutex.lock(); stop = true; mutex.unlock() }
    func begin() throws {
        guard rich else { return }
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { throw PatchError(message: "터미널 입력 설정을 읽지 못했습니다.") }
        resume()
        for number in [SIGINT, SIGTERM, SIGHUP] {
            oldSignals.append((number, signal(number, SIG_IGN)))
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [weak self] in
                guard let self else { return }; self.mutex.lock(); self.stop = true; self.mutex.unlock()
            }
            source.resume(); signals.append(source)
        }
    }
    func suspend() {
        guard active else { return }
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &original)
        write("\u{1b}[0m\u{1b}[?25h\u{1b}[?1049l")
        active = false
    }
    func resume() {
        guard rich, !active else { return }
        var raw = original
        cfmakeraw(&raw)
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        write("\u{1b}[?1049h\u{1b}[?25l")
        active = true
    }
    func write(_ text: String) {
        let data = Data(text.utf8)
        data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let count = Darwin.write(STDOUT_FILENO, buffer.baseAddress!.advanced(by: sent), buffer.count - sent)
                if count <= 0 { break }; sent += count
            }
        }
    }
    var size: (width: Int, height: Int) {
        var window = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &window) == 0, window.ws_col > 0, window.ws_row > 0 {
            return (Int(window.ws_col), Int(window.ws_row))
        }
        return (80, 24)
    }
    func key() -> TerminalKey {
        if wantsExit { return .quit }
        if !rich {
            guard let line = readLine() else { return .quit }
            return line.isEmpty ? .enter : TerminalKey.decode(Array(line.utf8))
        }
        if queued.isEmpty {
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 120) > 0 else { return .other }
            var bytes = [UInt8](repeating: 0, count: 64)
            let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
            if count <= 0 { return .quit }
            queued.append(contentsOf: bytes.prefix(count))
        }
        let first = queued.removeFirst()
        guard first == 27 else { return TerminalKey.decode([first]) }
        // Arrow bytes can arrive separately on a pseudo-terminal.
        while queued.count < 2 {
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 35) > 0 else { break }
            var byte: UInt8 = 0
            if Darwin.read(STDIN_FILENO, &byte, 1) == 1 { queued.append(byte) } else { break }
        }
        if queued.count >= 2, queued[0] == 91 || queued[0] == 79 {
            return TerminalKey.decode([first, queued.removeFirst(), queued.removeFirst()])
        }
        return .back
    }
    func draw(_ lines: [String]) {
        let bounds = size
        if !rich { write(lines.joined(separator: "\n") + "\n> "); return }
        var screen = "\u{1b}[H"
        for line in lines.prefix(max(1, bounds.height - 1)) {
            let text = TerminalText.fit(line, max(1, bounds.width - 4))
            let selected = text.hasPrefix("›")
            let gold = text.hasPrefix("DNF") || text.hasPrefix("━") || selected
            let escape = color ? (selected ? "\u{1b}[38;5;223;48;5;237m" : gold ? "\u{1b}[33m" : "") : ""
            if color && selected, let divider = text.range(of: " │ ") {
                screen += "\u{1b}[K  " + escape + text[..<divider.lowerBound] + "\u{1b}[0m" + text[divider.lowerBound...] + "\r\n"
            } else {
                screen += "\u{1b}[K  " + escape + text + (color ? "\u{1b}[0m" : "") + "\r\n"
            }
        }
        write(screen + "\u{1b}[J")
    }
    deinit {
        suspend()
        for source in signals { source.cancel() }
        for (number, previous) in oldSignals { signal(number, previous) }
    }
}

final class TerminalUI {
    let root: URL
    let helper: URL
    let snapshot: () -> MenuSnapshot
    let openHomepage: () -> Bool
    let keyboardStore: KeyProfileStore
    let activateKeyboard: (URL) throws -> Void
    static let normal: [MenuAction] = [.install, .diagnose, .restore, .homepage, .keyboard]
    static let advanced: [MenuAction] = [.selectApp, .setup, .connectionOnly]

    init(root: URL, helper: URL, snapshot: @escaping () -> MenuSnapshot, openHomepage: @escaping () -> Bool, keyboardStore: KeyProfileStore = KeyboardService.store, activateKeyboard: ((URL) throws -> Void)? = nil) {
        self.root = root; self.helper = helper; self.snapshot = snapshot; self.openHomepage = openHomepage
        self.keyboardStore = keyboardStore
        self.activateKeyboard = activateKeyboard ?? { try KeyboardService.startIfEnabled(wrapper: $0, executable: helper) }
    }
    static func run(root: URL) throws {
        guard let executable = Bundle.main.executableURL else { throw PatchError(message: "실행 도우미 경로를 찾지 못했습니다.") }
        try TerminalUI(root: root, helper: executable, snapshot: { MenuSnapshot.capture(root: root) },
                       openHomepage: { NSWorkspace.shared.open(URL(string: "https://df.nexon.com")!) }).run()
    }
    static func menuLines(snapshot: MenuSnapshot, selected: Int, advanced: Bool, width: Int) -> [String] {
        let actions = advanced ? Self.advanced : normal
        let chosen = actions[min(selected, actions.count - 1)]
        var lines = ["DNF   /   FOR MAC", "던전앤파이터 설치 매니저 · 개발 버전", String(repeating: "━", count: max(0, width)),
                     "● \(snapshot.installationLabel)   ·   웹 연결 \(snapshot.connected ? "등록됨" : "확인 필요")", ""]
        var menu = [advanced ? "고급 설정" : "무엇을 할까요?", ""]
        for (index, action) in actions.enumerated() {
            menu.append("\(index == selected ? "›" : " ") \(index + 1)  \(action.title)")
            menu.append("")
        }
        let detail = [chosen.title, "", chosen.detail, "", "설치 환경",
                      snapshot.appleSilicon ? "Apple Silicon" : "Intel / 아키텍처 확인 필요",
                      snapshot.rosetta ? "Rosetta: 준비됨 / 불필요" : "Rosetta: 설치 필요",
                      "D3DMetal: \(snapshot.metal ? "활성화" : "설치 시 확인")", "", "설치 위치", snapshot.wrapperPath ?? "설치 전"]
        if width >= 68 {
            let left = max(30, width / 2 - 2)
            let right = width - left - 3
            for row in 0..<max(menu.count, detail.count) {
                lines.append(TerminalText.pad(row < menu.count ? menu[row] : "", left) + " │ " + TerminalText.fit(row < detail.count ? detail[row] : "", right))
            }
        } else {
            lines += menu
            lines += [TerminalText.fit(chosen.detail, width)]
        }
        lines += ["", String(repeating: "─", count: max(0, width)), advanced ? "↑↓ / 숫자 선택  Enter 실행  Esc 돌아가기" : "↑↓ / 숫자 선택  Enter 실행  A 고급  Q 종료"]
        return lines.map { TerminalText.fit($0, width) }
    }
    func run() throws {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            throw PatchError(message: "대화형 터미널에서 던파.command를 열어 주세요. 자동화에는 기존 --install / --diagnose 명령을 사용하세요.")
        }
        setlocale(LC_CTYPE, "")
        let terminal = MenuTerminal()
        try terminal.begin()
        var current = snapshot()
        var selected = 0
        var advanced = false
        var previousFrame = ""
        while !terminal.wantsExit {
            let bounds = terminal.size
            let small = bounds.width < 36 || bounds.height < 22
            let lines = small ? ["DNF", "창을 36열 × 22줄 이상으로 늘려 주세요.", "Q 종료"] : Self.menuLines(snapshot: current, selected: selected, advanced: advanced, width: bounds.width - 4)
            let frame = "\(terminal.size.width)x\(terminal.size.height)" + lines.joined(separator: "\n")
            if frame != previousFrame || !terminal.rich { terminal.draw(lines); previousFrame = frame }
            let key = terminal.key()
            if key == .quit { return }
            if small { continue }
            let actions = advanced ? Self.advanced : Self.normal
            var action: MenuAction?
            switch key {
            case .up: selected = (selected + actions.count - 1) % actions.count
            case .down: selected = (selected + 1) % actions.count
            case .advanced: advanced = true; selected = 0
            case .back: advanced = false; selected = 0
            case .number(let number): if number < actions.count { selected = number; action = actions[number] }
            case .enter: action = actions[selected]
            default: break
            }
            if let action {
                try perform(action, terminal: terminal)
                current = snapshot(); previousFrame = ""
            }
        }
    }
    private func confirm(_ action: MenuAction, terminal: MenuTerminal) -> Bool {
        let text = action == .connectionOnly ? "폰트 복원 없이 백업을 보관하고 연결 기록만 정리합니다." : "원래 폰트 설정과 홈페이지 연결을 복원합니다."
        terminal.draw(["DNF   /   \(action.title)", "", text, "설치된 DNF.app과 게임 파일은 삭제하지 않습니다.", "", "[1] 취소하고 돌아가기   [2] 복원 진행"])
        while true {
            switch terminal.key() {
            case .number(1): return true
            case .quit: terminal.requestExit(); return false
            case .enter, .back, .number(0): return false
            default: break
            }
        }
    }
    private func perform(_ action: MenuAction, terminal: MenuTerminal) throws {
        if action == .keyboard {
            do {
                guard let path = snapshot().wrapperPath else { throw PatchError(message: "먼저 DNF.app을 설치해 주세요.") }
                try KeyboardEditor(wrapper: URL(fileURLWithPath:path), store:keyboardStore, activate:activateKeyboard).run(terminal:terminal)
            } catch { showResult(title: action.title, success:false, log:[error.localizedDescription], terminal:terminal) }
            return
        }
        if action == .homepage {
            showResult(title: action.title, success: openHomepage(), log: ["브라우저에서 로그인하고 GAME START를 눌러 주세요."], terminal: terminal)
            return
        }
        if [.restore, .connectionOnly].contains(action), !confirm(action, terminal: terminal) { return }
        var retry = true
        while retry && !terminal.wantsExit {
            retry = false
            do {
                let current = snapshot()
                let arguments = try action.arguments(snapshot: current, root: root)
                if action.installs && !current.rosetta {
                    terminal.suspend()
                    print("Rosetta가 필요합니다. 다음 Apple 약관을 직접 확인하고 동의하면 설치됩니다.")
                    let status = try InteractiveCommand.run(URL(fileURLWithPath: "/usr/sbin/softwareupdate"), arguments: ["--install-rosetta"])
                    terminal.resume()
                    guard status == 0 else { throw PatchError(message: "Rosetta 설치가 완료되지 않았습니다.") }
                }
                let job = try MenuJob(helper: helper, arguments: arguments)
                var details = false
                var exitAfterJob = false
                var frame = ""
                while job.process.isRunning {
                    job.collect()
                    let elapsed = Int(Date().timeIntervalSince(job.started))
                    let phase = job.log.lines.last ?? "작업을 시작하고 있습니다."
                    var lines = ["DNF   /   \(action.title)", "", "처리 중   ·   경과 \(elapsed / 60):\(String(format: "%02d", elapsed % 60))", "", phase, "", "파일 선택창이나 네오플 설치창이 열리면 안내를 따라 주세요."]
                    if details { lines += ["", "최근 작업 기록"] + job.log.lines.suffix(max(1, terminal.size.height - 12)) }
                    lines += ["", exitAfterJob ? "작업이 끝난 뒤 종료합니다. 창을 닫지 마세요." : "L 상세 로그   Q 작업 완료 후 종료"]
                    let next = "\(terminal.size.width)x\(terminal.size.height)" + lines.joined(separator: "\n")
                    if next != frame { terminal.draw(lines); frame = next }
                    if terminal.rich && !terminal.wantsExit {
                        let key = terminal.key()
                        if key == .logs { details.toggle() }
                        if key == .quit { exitAfterJob = true; terminal.requestExit() }
                    } else { Thread.sleep(forTimeInterval: 0.15) }
                }
                job.process.waitUntilExit(); job.collect(); job.log.append(Data(), final: true)
                if exitAfterJob || terminal.wantsExit { return }
                retry = showResult(title: action.title, success: job.process.terminationStatus == 0, log: job.log.lines, terminal: terminal)
            } catch {
                terminal.resume()
                retry = showResult(title: action.title, success: false, log: [error.localizedDescription], terminal: terminal)
            }
        }
    }
    @discardableResult
    private func showResult(title: String, success: Bool, log: [String], terminal: MenuTerminal) -> Bool {
        var details = false
        var previous = ""
        while !terminal.wantsExit {
            let summary = success ? "작업이 완료됐습니다." : "작업을 완료하지 못했습니다."
            let safe = log.map(TerminalText.clean)
            var lines = ["DNF   /   \(title)", "", "\(success ? "✓" : "!") \(summary)", ""]
            lines += Array(safe.suffix(details ? max(1, terminal.size.height - 9) : 4))
            lines += ["", success ? "Enter 메뉴로   L 상세 로그   Q 종료" : "R 재시도   L 상세 로그   Esc 메뉴로   Q 종료"]
            let frame = "\(terminal.size.width)x\(terminal.size.height)" + lines.joined(separator: "\n")
            if frame != previous || !terminal.rich { terminal.draw(lines); previous = frame }
            switch terminal.key() {
            case .logs: details.toggle()
            case .retry: if !success { return true }
            case .enter, .back: return false
            case .quit: terminal.requestExit(); return false
            default: break
            }
        }
        return false
    }
}
