import Foundation
import CryptoKit
import Darwin

struct GameSettings: Codable, Equatable {
    var commandToControl: Bool
    var leftOptionIsAlt: Bool
    var rightOptionIsAlt: Bool
    var d3dMetal: Bool
    var cncDDraw: Bool
}

struct GameSettingsError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum GameSettingsValue: Codable, Equatable {
    case absent, string(String), boolean(Bool)
}

struct GameSettingsSnapshot {
    var values: [String: GameSettingsValue]
    var globalValues: [String: String]

    var settings: GameSettings {
        func flag(_ key: String) -> Bool {
            if case .string(let value) = values[key] { return value.uppercased() != "N" }
            return globalValues[key]?.uppercased() != "N"
        }
        func renderer(_ key: String) -> Bool {
            if case .boolean(let value) = values[key] { return value }; return false
        }
        return GameSettings(commandToControl: flag("LeftCommandIsCtrl") || flag("RightCommandIsCtrl"),
            leftOptionIsAlt: flag("LeftOptionIsAlt"), rightOptionIsAlt: flag("RightOptionIsAlt"),
            d3dMetal: renderer("D3DMETAL"), cncDDraw: renderer("CNC_DDRAW"))
    }
}

protocol GameSettingsIO {
    func isGameRunning(wrapper: URL) throws -> Bool
    func read(wrapper: URL) throws -> GameSettingsSnapshot
    func readForMutation(wrapper: URL) throws -> GameSettingsSnapshot
    func write(_ changes: [String: GameSettingsValue], wrapper: URL) throws
}

extension GameSettingsIO {
    func readForMutation(wrapper: URL) throws -> GameSettingsSnapshot { try read(wrapper: wrapper) }
}

/// Desired settings and a write-ahead ownership journal are separate from the live wrapper.
/// Callers should serialize this service with the existing patch lock.
struct GameSettingsService {
    let directory: URL
    let io: GameSettingsIO
    let legacyBackup: URL

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DNF Sikarugir Patch/Keyboard/GameSettings"),
         io: GameSettingsIO = WineGameSettingsIO(), legacyBackup: URL? = nil) {
        self.directory = directory; self.io = io
        self.legacyBackup = legacyBackup ?? directory.deletingLastPathComponent().appendingPathComponent("command-control-original.json")
    }

    private struct State: Codable {
        var version = 1
        var wrapperPath: String
        var desired: GameSettings?
        var committed: GameSettings?
        var original: [String: GameSettingsValue] = [:]
        var applied: [String: GameSettingsValue] = [:]
        // An interrupted write may leave any prior or attempted value live, per key.
        // Optional for journals written before incomplete-attempt tracking existed.
        var previousApplied: [String: [GameSettingsValue]]?
        func owns(_ value: GameSettingsValue, key: String) -> Bool {
            applied[key] == value || previousApplied?[key]?.contains(value) == true
        }
        var legacyConsidered = false
    }

    func read(wrapper: URL) throws -> GameSettings {
        let state = try load(wrapper: wrapper)
        if let desired = state?.desired { return desired }
        return try io.read(wrapper: wrapper).settings
    }

    func save(_ settings: GameSettings, wrapper: URL) throws {
        var state = try load(wrapper: wrapper) ?? State(wrapperPath: identity(wrapper))
        state.desired = settings
        try persist(state, wrapper: wrapper)
    }

    func hasPending(wrapper: URL) throws -> Bool {
        guard let state = try load(wrapper: wrapper), let desired = state.desired else { return false }
        return desired != state.committed || state.previousApplied != nil
    }

    /// False means the game is running and the request remains queued. Reads are offline.
    @discardableResult func applyPending(wrapper: URL) throws -> Bool {
        guard try !io.isGameRunning(wrapper: wrapper) else { return false }
        let live = try io.readForMutation(wrapper: wrapper)
        var state = try load(wrapper: wrapper) ?? State(wrapperPath: identity(wrapper))
        adoptLegacy(into: &state, live: live, wrapper: wrapper)
        guard let desired = state.desired else {
            if !state.applied.isEmpty { try persist(state, wrapper: wrapper) }
            return true
        }
        let requested = Self.values(desired)
        var changes: [String: GameSettingsValue] = [:]
        var previous = state.previousApplied ?? [:]
        for (key, value) in requested {
            let current = live.values[key] ?? .absent
            var owned = previous[key] ?? []
            if let applied = state.applied[key], !owned.contains(applied) { owned.append(applied) }
            if !owned.contains(current) {
                // A value outside the whole incomplete ownership set is an external edit.
                state.original[key] = current
                owned = []
            }
            previous[key] = owned
            state.applied[key] = value
            if current != value { changes[key] = value }
        }
        state.previousApplied = previous
        // Persist both the previous owned values and the next attempted values before writing.
        try persist(state, wrapper: wrapper)
        guard try changes.isEmpty || !io.isGameRunning(wrapper: wrapper) else { return false }
        if !changes.isEmpty { try io.write(changes, wrapper: wrapper) }
        state.committed = desired
        state.previousApplied = nil
        try persist(state, wrapper: wrapper)
        return true
    }

    @discardableResult func restore(wrapper: URL) throws -> Bool {
        guard try !io.isGameRunning(wrapper: wrapper) else { return false }
        let live = try io.readForMutation(wrapper: wrapper)
        var state = try load(wrapper: wrapper) ?? State(wrapperPath: identity(wrapper))
        adoptLegacy(into: &state, live: live, wrapper: wrapper)
        var changes: [String: GameSettingsValue] = [:]
        for key in state.applied.keys {
            let current = live.values[key] ?? .absent
            if state.owns(current, key: key), let original = state.original[key], original != current {
                changes[key] = original
            }
        }
        // Retain the journal until all writes succeed, including a failure after registry import.
        if !state.applied.isEmpty { try persist(state, wrapper: wrapper) }
        guard try changes.isEmpty || !io.isGameRunning(wrapper: wrapper) else { return false }
        if !changes.isEmpty { try io.write(changes, wrapper: wrapper) }
        state.desired = nil; state.committed = nil; state.original = [:]; state.applied = [:]; state.previousApplied = nil
        try persist(state, wrapper: wrapper)
        return true
    }

    func status(wrapper: URL) -> String {
        do {
            guard let state = try load(wrapper: wrapper), state.desired != nil else { return "현재 게임 설정 사용 중" }
            return try hasPending(wrapper: wrapper) ? "저장됨 · 게임 종료 후 또는 다음 실행 전 적용 대기" : "게임 설정 적용됨"
        }
        catch { return "게임 설정 확인 실패 · \(error.localizedDescription)" }
    }

    private static func values(_ settings: GameSettings) -> [String: GameSettingsValue] {
        ["LeftCommandIsCtrl": .string(settings.commandToControl ? "Y" : "N"),
         "RightCommandIsCtrl": .string(settings.commandToControl ? "Y" : "N"),
         "LeftOptionIsAlt": .string(settings.leftOptionIsAlt ? "Y" : "N"),
         "RightOptionIsAlt": .string(settings.rightOptionIsAlt ? "Y" : "N"),
         "D3DMETAL": .boolean(settings.d3dMetal), "CNC_DDRAW": .boolean(settings.cncDDraw)]
    }

    private func identity(_ wrapper: URL) -> String { wrapper.standardizedFileURL.resolvingSymlinksInPath().path }
    private func file(_ wrapper: URL) -> URL {
        let digest = SHA256.hash(data: Data(identity(wrapper).utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("settings-\(digest).json")
    }
    private func load(wrapper: URL) throws -> State? {
        let url = file(wrapper)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 65536 else { throw GameSettingsError(message: "게임 설정 백업 파일이 너무 큽니다.") }
        let state = try JSONDecoder().decode(State.self, from: data)
        let allowed = Set(WineGameSettingsIO.appKeys + WineGameSettingsIO.infoKeys)
        guard state.version == 1, state.wrapperPath == identity(wrapper),
              Set(state.original.keys).isSubset(of: allowed), Set(state.applied.keys).isSubset(of: allowed),
              Set(state.previousApplied?.keys.map { $0 } ?? []).isSubset(of: allowed) else {
            throw GameSettingsError(message: "다른 앱 또는 지원하지 않는 게임 설정 백업입니다.")
        }
        return state
    }
    private func persist(_ state: State, wrapper: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: file(wrapper), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file(wrapper).path)
    }
    private func adoptLegacy(into state: inout State, live: GameSettingsSnapshot, wrapper: URL) {
        guard !state.legacyConsidered else { return }
        state.legacyConsidered = true
        guard let data = try? Data(contentsOf: legacyBackup), data.count <= 65536,
              let legacy = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let path = legacy["wrapperPath"] as? String, identity(URL(fileURLWithPath: path)) == identity(wrapper),
              let originals = legacy["appValues"] as? [String: String] else { return }
        for key in ["LeftCommandIsCtrl", "RightCommandIsCtrl"] where state.applied[key] == nil && live.values[key] == .string("N") {
            let original: GameSettingsValue
            if let raw = originals[key] {
                let decoded = (try? JSONDecoder().decode(String.self, from: Data(raw.utf8))) ?? raw
                guard decoded == "Y" || decoded == "N" else { continue }
                original = .string(decoded)
            } else { original = .absent }
            state.original[key] = original; state.applied[key] = .string("N")
        }
    }
}

struct WineGameSettingsIO: GameSettingsIO {
    var gameRunning: ((URL) throws -> Bool)?
    var wineProcess: ([String], URL) -> Process? = { makeWineProcess(arguments: $0, wrapper: $1) }
    static let appKeys = ["LeftCommandIsCtrl", "RightCommandIsCtrl", "LeftOptionIsAlt", "RightOptionIsAlt"]
    static let infoKeys = ["D3DMETAL", "CNC_DDRAW"]
    private static let appSection = #"Software\\Wine\\AppDefaults\\DNF.exe\\Mac Driver"#
    private static let globalSection = #"Software\\Wine\\Mac Driver"#

    func isGameRunning(wrapper: URL) throws -> Bool {
        if let gameRunning { return try gameRunning(wrapper) }
        // comm contains executable identities only. Never inspect argv/launch authentication URLs.
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/ps"); process.arguments = ["-axo", "comm="]
        let result = try run(process, timeout: 3)
        guard result.status == 0, let commands = String(data: result.output, encoding: .utf8) else {
            throw GameSettingsError(message: "게임 실행 상태를 확인하지 못해 설정을 적용하지 않았습니다.")
        }
        return commands.split(separator: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "/").split(separator: "/").last?.lowercased() == "dnf.exe"
        }
    }

    func read(wrapper: URL) throws -> GameSettingsSnapshot {
        let registry = wrapper.appendingPathComponent("Contents/SharedSupport/prefix/user.reg")
        let handle = try FileHandle(forReadingFrom: registry); defer { try? handle.close() }
        var buffer = Data(); var section = ""; var globals: [String: String] = [:]
        var values = Dictionary(uniqueKeysWithValues: Self.appKeys.map { ($0, GameSettingsValue.absent) })
        func consume(_ lineData: Data) throws {
            guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            if line.hasPrefix("["), let end = line.firstIndex(of: "]") { section = String(line[line.index(after: line.startIndex)..<end]); return }
            guard section.caseInsensitiveCompare(Self.appSection) == .orderedSame || section.caseInsensitiveCompare(Self.globalSection) == .orderedSame else { return }
            for key in Self.appKeys {
                let prefix = "\"\(key)\"="
                guard line.lowercased().hasPrefix(prefix.lowercased()) else { continue }
                let raw = String(line.dropFirst(prefix.count))
                guard let value = try? JSONDecoder().decode(String.self, from: Data(raw.utf8)) else {
                    throw GameSettingsError(message: "\(key) 레지스트리 형식을 안전하게 복원할 수 없습니다.")
                }
                if section.caseInsensitiveCompare(Self.appSection) == .orderedSame { values[key] = .string(value) } else { globals[key] = value }
            }
        }
        // Stream the file instead of exporting/retaining the registry or unrelated sections.
        while let chunk = try handle.read(upToCount: 8192), !chunk.isEmpty {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                try consume(Data(buffer[..<newline])); buffer.removeSubrange(...newline)
            }
            guard buffer.count <= 1024 * 1024 else { throw GameSettingsError(message: "레지스트리 줄이 너무 깁니다.") }
        }
        if !buffer.isEmpty { try consume(buffer) }
        let (info, _, _) = try readInfo(wrapper)
        for key in Self.infoKeys {
            if let value = info[key] as? NSNumber { values[key] = .boolean(value.boolValue) }
            else if info[key] == nil { values[key] = .absent }
            else { throw GameSettingsError(message: "\(key) 렌더러 설정 형식을 확인해 주세요.") }
        }
        return GameSettingsSnapshot(values: values, globalValues: globals)
    }

    func readForMutation(wrapper: URL) throws -> GameSettingsSnapshot {
        guard try !isGameRunning(wrapper: wrapper) else { throw GameSettingsError(message: "게임 종료 후 설정을 적용해 주세요.") }
        var snapshot = try read(wrapper: wrapper)
        let query = try runWine(["C:\\windows\\system32\\reg.exe", "query", "HKCU\\Software\\Wine\\AppDefaults\\DNF.exe\\Mac Driver"], wrapper: wrapper)
        if query.status == 1 {
            // A missing app key is normal. First verify Wine can actually execute commands.
            guard try runWine(["C:\\windows\\system32\\cmd.exe", "/c", "exit", "0"], wrapper: wrapper).status == 0 else {
                throw GameSettingsError(message: "Wine 실행 상태를 확인하지 못해 원본 설정을 저장하지 않았습니다.")
            }
            for key in Self.appKeys { snapshot.values[key] = .absent }
            return snapshot
        }
        guard query.status == 0 else { throw GameSettingsError(message: "던파 전용 원본 키보드 설정을 읽지 못했습니다.") }
        let text: String?
        if query.output.starts(with: [0xff, 0xfe]) || query.output.contains(0) {
            text = String(data: query.output, encoding: .utf16LittleEndian)
        } else { text = String(data: query.output, encoding: .utf8) }
        guard let text else { throw GameSettingsError(message: "키보드 레지스트리 응답을 해석하지 못했습니다.") }
        for key in Self.appKeys { snapshot.values[key] = .absent }
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard let rawKey = fields.first, let key = Self.appKeys.first(where: { $0.caseInsensitiveCompare(String(rawKey)) == .orderedSame }) else { continue }
            guard fields.count >= 3, fields[1] == "REG_SZ", let range = line.range(of: "REG_SZ") else {
                throw GameSettingsError(message: "키보드 레지스트리 원본 형식을 안전하게 복원할 수 없습니다.")
            }
            snapshot.values[key] = .string(line[range.upperBound...].trimmingCharacters(in: .whitespaces))
        }
        return snapshot
    }

    private func runWine(_ arguments: [String], wrapper: URL) throws -> (status: Int32, output: Data) {
        guard try !isGameRunning(wrapper: wrapper), let process = wineProcess(arguments, wrapper) else {
            throw GameSettingsError(message: "게임이 실행 중이거나 Wine을 찾지 못했습니다.")
        }
        return try run(process, timeout: 15)
    }

    private func run(_ process: Process, timeout: TimeInterval) throws -> (status: Int32, output: Data) {
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        final class Capture: @unchecked Sendable { var data = Data() }
        let capture = Capture(); let group = DispatchGroup()
        try process.run()
        group.enter()
        DispatchQueue.global(qos: .utility).async { capture.data = output.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate(); kill(process.processIdentifier, SIGKILL)
            throw GameSettingsError(message: "설정 작업 시간이 초과됐습니다. 게임 종료 후 다시 시도해 주세요.")
        }
        guard group.wait(timeout: .now() + 1) == .success, capture.data.count <= 1024 * 1024 else {
            throw GameSettingsError(message: "설정 응답을 안전하게 읽지 못했습니다.")
        }
        return (process.terminationStatus, capture.data)
    }

    func write(_ changes: [String: GameSettingsValue], wrapper: URL) throws {
        guard Set(changes.keys).isSubset(of: Set(Self.appKeys + Self.infoKeys)) else {
            throw GameSettingsError(message: "지원하지 않는 게임 설정입니다.")
        }
        guard try !isGameRunning(wrapper: wrapper) else { throw GameSettingsError(message: "게임 종료 후 설정을 적용해 주세요.") }
        var registryLines: [String] = []
        for key in Self.appKeys {
            guard let value = changes[key] else { continue }
            switch value {
            case .absent: registryLines.append("\"\(key)\"=-")
            case .string(let string):
                let escaped = string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                guard !string.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw GameSettingsError(message: "잘못된 레지스트리 문자열입니다.") }
                registryLines.append("\"\(key)\"=\"\(escaped)\"")
            case .boolean: throw GameSettingsError(message: "키보드 설정은 문자열이어야 합니다.")
            }
        }
        if !registryLines.isEmpty {
            let name = "dnf-game-settings-\(UUID().uuidString).reg"
            let temp = wrapper.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/windows/temp")
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let file = temp.appendingPathComponent(name); defer { try? FileManager.default.removeItem(at: file) }
            let text = "Windows Registry Editor Version 5.00\r\n\r\n[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\DNF.exe\\Mac Driver]\r\n" + registryLines.joined(separator: "\r\n") + "\r\n"
            var data = Data([0xff, 0xfe]); data.append(text.data(using: .utf16LittleEndian)!)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            guard try !isGameRunning(wrapper: wrapper), let process = wineProcess(["C:\\windows\\system32\\reg.exe", "import", "C:\\windows\\temp\\" + name], wrapper) else {
                throw GameSettingsError(message: "게임이 실행 중이거나 Wine을 찾지 못했습니다. 설정 적용을 기다립니다.")
            }
            guard try run(process, timeout: 15).status == 0 else { throw GameSettingsError(message: "던파 전용 키보드 설정을 적용하지 못했습니다.") }

        }
        if Self.infoKeys.contains(where: { changes[$0] != nil }) {
            guard try !isGameRunning(wrapper: wrapper) else { throw GameSettingsError(message: "게임 종료 후 렌더러 설정을 적용해 주세요.") }
            var (info, original, format) = try readInfo(wrapper)
            for key in Self.infoKeys {
                guard let value = changes[key] else { continue }
                switch value {
                case .absent: info.removeValue(forKey: key)
                case .boolean(let flag): info[key] = flag
                case .string: throw GameSettingsError(message: "렌더러 설정은 켜기/끄기 값이어야 합니다.")
                }
            }
            let file = wrapper.appendingPathComponent("Contents/Info.plist")
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: format, options: 0)
            guard try Data(contentsOf: file) == original else { throw GameSettingsError(message: "다른 작업이 앱 설정을 변경했습니다. 다시 시도해 주세요.") }
            try data.write(to: file, options: .atomic)
        }
    }

    private func readInfo(_ wrapper: URL) throws -> ([String: Any], Data, PropertyListSerialization.PropertyListFormat) {
        let data = try Data(contentsOf: wrapper.appendingPathComponent("Contents/Info.plist"))
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let info = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
            throw GameSettingsError(message: "앱 렌더러 설정을 읽지 못했습니다.")
        }
        return (info, data, format)
    }
}
