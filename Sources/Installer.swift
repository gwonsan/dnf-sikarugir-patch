import AppKit
import CoreServices

let patchBundleID = "io.github.dnf-sikarugir-patch.launcher"

struct PatchState: Codable {
    let wrapperPath: String
    let previousHandler: String?
    let originalFonts: [String: String]
    var installed: Bool?
}

struct PatchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Installer {
    static let fm = FileManager.default
    static var support: URL { fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DNF Sikarugir Patch") }
    static var stateFile: URL { support.appendingPathComponent("state.plist") }
    static var destination: URL { fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/DNF Web Launcher.app") }

    static func readState() throws -> PatchState {
        try PropertyListDecoder().decode(PatchState.self, from: Data(contentsOf: stateFile))
    }

    static func save(_ state: PatchState) throws {
        try fm.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try PropertyListEncoder().encode(state)
        try data.write(to: stateFile, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateFile.path)
    }

    static func handler() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "neople://patch-check")!) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    static func bridgeIsRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: patchBundleID)
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    @discardableResult
    static func run(_ executable: URL, _ args: [String], environment: [String: String]? = nil, timeout: TimeInterval = 60, log: URL? = nil) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        var output: FileHandle?
        if let log {
            try fm.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw PatchError(message: "초기화 로그를 만들지 못했습니다: \(log.path)")
            }
            output = try FileHandle(forWritingTo: log)
        }
        defer { try? output?.close() }
        process.standardOutput = output ?? FileHandle.nullDevice
        process.standardError = output ?? FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard !process.isRunning else {
            process.terminate()
            throw PatchError(message: "설정 작업 시간이 초과됐습니다. 게임/다운로드가 끝난 뒤 다시 설치해 주세요.")
        }
        return process.terminationStatus
    }

    @discardableResult
    static func wine(_ wrapper: URL, _ args: [String]) throws -> Int32 {
        guard let process = makeLaunchProcess(request: "neople://patch-diagnostic", wrapper: wrapper),
              let executable = process.executableURL else {
            throw PatchError(message: "Sikarugir Wine 또는 NeopleCustomURLStarter.exe가 없는 앱입니다.")
        }
        return try run(executable, args, environment: process.environment)
    }

    static func chooseWrapper(_ argument: String?) throws -> URL {
        if let argument { return URL(fileURLWithPath: argument).standardizedFileURL }
        let candidates = ["Applications/Sikarugir/DNF.app", "Applications/DNF.app"].map {
            fm.homeDirectoryForCurrentUser.appendingPathComponent($0)
        }.filter { makeLaunchProcess(request: "neople://patch-check", wrapper: $0) != nil }
        if candidates.count == 1 { return candidates[0] }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "던파를 설치한 Sikarugir 앱을 선택하세요"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let url = panel.url else {
            throw PatchError(message: "앱 선택을 취소했습니다.")
        }
        return url.standardizedFileURL
    }

    @discardableResult
    static func registry(_ wrapper: URL, import text: String? = nil) throws -> [String: String] {
        let name = "dnf-patch-" + UUID().uuidString
        let directory = wrapper.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/windows/temp/" + name)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let file = directory.appendingPathComponent("fonts.reg")
        let windowsPath = "C:\\windows\\temp\\" + name + "\\fonts.reg"
        if let text {
            guard let data = text.data(using: .utf16) else { throw PatchError(message: "한글 설정 파일을 만들지 못했습니다.") }
            try data.write(to: file)
            guard try wine(wrapper, ["C:\\windows\\system32\\reg.exe", "import", windowsPath]) == 0 else {
                throw PatchError(message: "폰트 레지스트리를 적용하지 못했습니다. 복원.command로 되돌릴 수 있습니다.")
            }
            return [:]
        }
        let code = try wine(wrapper, ["C:\\windows\\system32\\reg.exe", "export", "HKCU\\Software\\Wine\\Fonts\\Replacements", windowsPath, "/y"])
        if code != 0 {
            // Verify Wine itself before interpreting a missing key as an empty snapshot.
            guard try wine(wrapper, ["C:\\windows\\system32\\cmd.exe", "/c", "exit 0"]) == 0 else {
                throw PatchError(message: "Wine 진단에 실패했습니다. 앱과 Rosetta 설치를 확인해 주세요.")
            }
            guard try wine(wrapper, ["C:\\windows\\system32\\reg.exe", "query", "HKCU\\Software\\Wine\\Fonts\\Replacements"]) != 0 else {
                throw PatchError(message: "기존 폰트 설정을 백업하지 못했습니다.")
            }
            return [:]
        }
        guard let text = String(data: try Data(contentsOf: file), encoding: .utf16) else {
            throw PatchError(message: "기존 폰트 백업을 읽지 못했습니다.")
        }
        return FontPatch.snapshot(text)
    }

    static func install(_ wrapper: URL) throws {
        guard makeLaunchProcess(request: "neople://patch-check", wrapper: wrapper) != nil else {
            throw PatchError(message: "선택한 앱에 Wine 또는 네오플 플러그인이 없습니다. Sikarugir에 네오플 플러그인을 먼저 설치해 주세요.")
        }
        guard try wine(wrapper, ["C:\\windows\\system32\\cmd.exe", "/c", "exit 0"]) == 0 else {
            throw PatchError(message: "Wine 실행 진단에 실패했습니다. Sikarugir Wine 11 및 Rosetta가 필요합니다.")
        }
        let existing = fm.fileExists(atPath: stateFile.path) ? try readState() : nil
        if let existing, existing.wrapperPath != wrapper.path {
            throw PatchError(message: "다른 앱에 적용한 패치가 있습니다. 먼저 복원.command를 실행해 주세요.")
        }
        let source = Bundle.main.bundleURL
        guard source != destination else {
            throw PatchError(message: "압축을 푼 패치 폴더의 설치.command를 실행해 주세요.")
        }
        if fm.fileExists(atPath: destination.path) {
            guard existing != nil, Bundle(url: destination)?.bundleIdentifier == patchBundleID else {
                throw PatchError(message: "설치 경로에 기존 앱이 있습니다. ~/Applications/DNF Web Launcher.app을 확인해 주세요.")
            }
            guard !bridgeIsRunning() else {
                throw PatchError(message: "DNF Web Launcher를 종료한 뒤 다시 설치해 주세요. 다운로드 창은 종료할 필요가 없습니다.")
            }
        }
        var state = try existing ?? PatchState(wrapperPath: wrapper.path, previousHandler: handler(), originalFonts: registry(wrapper), installed: false)
        if existing == nil { try save(state) }
        print("한글 폰트 확인 중…")
        let font = wrapper.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/windows/Fonts/sourcehansans.ttc")
        if !fm.fileExists(atPath: font.path) {
            print("Sikarugir의 fakekorean으로 폰트를 설치합니다. 처음에는 다운로드가 필요합니다.")
            let launcher = wrapper.appendingPathComponent("Contents/MacOS/Sikarugir")
            guard try run(launcher, ["WSS-winetricks", "fakekorean"], timeout: 600) == 0,
                  fm.fileExists(atPath: font.path) else {
                throw PatchError(message: "fakekorean 폰트 설치에 실패했습니다. 게임/다운로드가 끝난 뒤 다시 실행해 주세요.")
            }
        }
        let currentFonts = try registry(wrapper)
        let fontDocument = FontPatch.installation(current: state.installed == true ? currentFonts : nil)
        try registry(wrapper, import: fontDocument)
        let fonts = try registry(wrapper)
        guard FontPatch.snapshot(fontDocument).keys.allSatisfy({ FontPatch.isOwned($0, fonts[$0]) }) else {
            throw PatchError(message: "한글 폰트 설정 검증에 실패했습니다.")
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staged = destination.deletingLastPathComponent().appendingPathComponent("DNF-patch-\(UUID().uuidString).app")
        try fm.copyItem(at: source, to: staged)
        defer { try? fm.removeItem(at: staged) }
        guard try run(URL(fileURLWithPath: "/usr/bin/codesign"), ["--verify", "--deep", staged.path]) == 0 else {
            throw PatchError(message: "패치 앱 서명 확인에 실패했습니다.")
        }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: staged, to: destination)
        guard LSRegisterURL(destination as CFURL, true) == noErr,
              LSSetDefaultHandlerForURLScheme("neople" as CFString, patchBundleID as CFString) == noErr,
              handler() == patchBundleID else {
            throw PatchError(message: "홈페이지 실행 연결 등록에 실패했습니다. 복원.command로 되돌릴 수 있습니다.")
        }
        state.installed = true
        try save(state)
        print("설치 완료. 다운로드가 끝나면 런처를 종료하고 던파 홈페이지에서 GAME START를 눌러 주세요.")
    }

    static func uninstall() throws {
        let state = try readState()
        let wrapper = URL(fileURLWithPath: state.wrapperPath)
        guard !bridgeIsRunning() else {
            throw PatchError(message: "DNF Web Launcher를 종료한 뒤 복원해 주세요.")
        }
        let current = try registry(wrapper)
        try registry(wrapper, import: FontPatch.restoration(original: state.originalFonts, current: current))
        if handler() == patchBundleID, let previous = state.previousHandler, previous != patchBundleID {
            guard LSSetDefaultHandlerForURLScheme("neople" as CFString, previous as CFString) == noErr else {
                throw PatchError(message: "이전 홈페이지 실행 연결을 복원하지 못했습니다. 백업은 유지됩니다.")
            }
        }
        if Bundle(url: destination)?.bundleIdentifier == patchBundleID { try fm.removeItem(at: destination) }
        try fm.removeItem(at: stateFile)
        print("복원 완료. 최초 폰트 설정을 복원했고 이후 바꾼 설정은 유지했습니다.")
    }

    static func diagnose(_ wrapper: URL) throws {
        guard try wine(wrapper, ["C:\\windows\\system32\\cmd.exe", "/c", "exit 0"]) == 0 else {
            throw PatchError(message: "Wine 실행 실패")
        }
        let fonts = try registry(wrapper)
        print("Wine 실행: 통과")
        print("한글 폰트 매핑: \(FontPatch.aliases.filter { FontPatch.isOwned($0, fonts[$0]) }.count)/16")
        print("홈페이지 연결: \(handler() == patchBundleID ? "패치 앱" : "다른 앱 또는 미등록")")
        print("게임 플레이와 화면의 한글 표시 확인은 별도로 필요합니다.")
    }
}
