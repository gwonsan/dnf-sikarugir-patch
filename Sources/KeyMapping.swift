import Foundation
import CryptoKit

struct KeyMappingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct KeyChoice: Equatable {
    let code: UInt16
    let name: String
}

enum KeyCatalog {
    // Physical macOS virtual keycodes. Wine keeps its own keyboard-layout interpretation.
    static let keys: [KeyChoice] = {
        let rows: [(UInt16, String)] = [
            (55,"왼쪽 Command"),(54,"오른쪽 Command"),(59,"왼쪽 Control"),(62,"오른쪽 Control"),
            (58,"왼쪽 Option / Alt"),(61,"오른쪽 Option / Alt"),(56,"왼쪽 Shift"),(60,"오른쪽 Shift"),(57,"Caps Lock"),
            (0,"A"),(11,"B"),(8,"C"),(2,"D"),(14,"E"),(3,"F"),(5,"G"),(4,"H"),(34,"I"),(38,"J"),(40,"K"),(37,"L"),(46,"M"),
            (45,"N"),(31,"O"),(35,"P"),(12,"Q"),(15,"R"),(1,"S"),(17,"T"),(32,"U"),(9,"V"),(13,"W"),(7,"X"),(16,"Y"),(6,"Z"),
            (29,"0"),(18,"1"),(19,"2"),(20,"3"),(21,"4"),(23,"5"),(22,"6"),(26,"7"),(28,"8"),(25,"9"),
            (49,"Space"),(36,"Enter"),(48,"Tab"),(51,"Backspace"),(53,"Escape"),(117,"Delete"),
            (123,"←"),(124,"→"),(125,"↓"),(126,"↑"),(115,"Home"),(119,"End"),(116,"Page Up"),(121,"Page Down"),
            (50,"`"),(27,"-"),(24,"="),(33,"["),(30,"]"),(42,"\\"),(41,";"),(39,"'"),(43,","),(47,"."),(44,"/"),
            (122,"F1"),(120,"F2"),(99,"F3"),(118,"F4"),(96,"F5"),(97,"F6"),(98,"F7"),(100,"F8"),(101,"F9"),(109,"F10"),(103,"F11"),(111,"F12"),
            (105,"F13"),(107,"F14"),(113,"F15"),(106,"F16"),(64,"F17"),(79,"F18"),(80,"F19"),(90,"F20"),
            (82,"키패드 0"),(83,"키패드 1"),(84,"키패드 2"),(85,"키패드 3"),(86,"키패드 4"),(87,"키패드 5"),(88,"키패드 6"),(89,"키패드 7"),(91,"키패드 8"),(92,"키패드 9"),
            (65,"키패드 ."),(67,"키패드 *"),(69,"키패드 +"),(75,"키패드 /"),(78,"키패드 -"),(81,"키패드 ="),(76,"키패드 Enter"),(71,"키패드 Clear")
        ]
        return rows.map { KeyChoice(code: $0.0, name: $0.1) }
    }()
    static func name(_ code: UInt16) -> String { keys.first { $0.code == code }?.name ?? "알 수 없는 키" }
    static func contains(_ code: UInt16) -> Bool { keys.contains { $0.code == code } }
    // Generic + left/right device-specific NSEvent flags. Caps Lock is a latch, handled separately.
    static let modifiers: [UInt16: (generic: UInt64, side: UInt64)] = [
        55:(0x100000,0x8),54:(0x100000,0x10),56:(0x20000,0x2),60:(0x20000,0x4),
        59:(0x40000,0x1),62:(0x40000,0x2000),58:(0x80000,0x20),61:(0x80000,0x40)
    ]
}

enum KeyTarget: Codable, Equatable {
    case key(UInt16), toggleInputSource, disabled
    var label: String {
        switch self {
        case .key(let code): return KeyCatalog.name(code)
        case .toggleInputSource: return "한/영 전환 (단독 누르기)"
        case .disabled: return "입력 안 함"
        }
    }
}

struct KeyBinding: Codable, Equatable {
    var source: UInt16
    var target: KeyTarget
}

enum KeyboardBackend: String, Codable, CaseIterable {
    case automatic, karabiner, native
    var label: String { switch self { case .automatic: return "자동 선택"; case .karabiner: return "Karabiner 우선"; case .native: return "자체 매핑" } }
}

struct KeyProfile: Codable, Equatable {
    var version = 1
    var wrapperPath: String
    var enabled = false
    var backend: KeyboardBackend = .automatic
    var bindings: [KeyBinding] = []
    init(wrapperPath: String) { self.wrapperPath = wrapperPath }
    private enum CodingKeys: String, CodingKey { case version, wrapperPath, enabled, backend, bindings }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self,forKey:.version)
        wrapperPath = try values.decode(String.self,forKey:.wrapperPath)
        enabled = try values.decode(Bool.self,forKey:.enabled)
        backend = try values.decodeIfPresent(KeyboardBackend.self,forKey:.backend) ?? .automatic
        bindings = try values.decode([KeyBinding].self,forKey:.bindings)
    }
    var usesCapsLock: Bool { bindings.contains { $0.source == 57 || $0.target == .key(57) } }
    mutating func useKoreanPreset() {
        for binding in [KeyBinding(source: 61, target: .toggleInputSource), KeyBinding(source: 57, target: .key(57))] {
            bindings.removeAll { $0.source == binding.source }; bindings.append(binding)
        }
    }
    func validate() throws {
        guard version == 1, URL(fileURLWithPath: wrapperPath).path == wrapperPath, wrapperPath.hasPrefix("/"), wrapperPath.hasSuffix(".app"),
              !wrapperPath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains), bindings.count <= KeyCatalog.keys.count else {
            throw KeyMappingError(message: "지원하지 않는 키 매핑 파일입니다.")
        }
        var sources = Set<UInt16>()
        for binding in bindings {
            guard KeyCatalog.contains(binding.source), sources.insert(binding.source).inserted else {
                throw KeyMappingError(message: "중복되거나 지원하지 않는 입력 키가 있습니다.")
            }
            if case .key(let target) = binding.target, !KeyCatalog.contains(target) {
                throw KeyMappingError(message: "지원하지 않는 대상 키입니다.")
            }
        }
    }
}

struct KeyProfileStore {
    let directory: URL
    func url(wrapper: URL) -> URL {
        let identity = wrapper.standardizedFileURL.resolvingSymlinksInPath().path
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format:"%02x", $0) }.joined()
        return directory.appendingPathComponent("keyboard-\(hash).json")
    }
    func load(wrapper: URL) throws -> KeyProfile {
        let path = wrapper.standardizedFileURL.resolvingSymlinksInPath().path
        let file = url(wrapper: wrapper)
        guard FileManager.default.fileExists(atPath: file.path) else { return KeyProfile(wrapperPath: path) }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard data.count <= 65536 else { throw KeyMappingError(message: "키 매핑 파일이 너무 큽니다.") }
        let profile = try JSONDecoder().decode(KeyProfile.self, from: data)
        try profile.validate()
        guard profile.wrapperPath == path else { throw KeyMappingError(message: "다른 앱의 키 매핑 파일입니다.") }
        return profile
    }
    func save(_ profile: KeyProfile) throws {
        try profile.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: url(wrapper: URL(fileURLWithPath: profile.wrapperPath)), options: .atomic)
    }
}

enum MappedKeyEvent: Equatable {
    case down(UInt16), up(UInt16), caps(Bool), inputSource
}

final class KeyMappingState {
    private let bindings: [UInt16: KeyTarget]
    private var held: [UInt16: KeyTarget] = [:]
    private var counts: [UInt16: Int] = [:]
    private var order: [UInt16] = []
    private var interrupted = Set<UInt16>()
    private var physicalDown: Set<UInt16>
    private var ignoredUntilRelease: Set<UInt16>
    private(set) var capsLock = false
    init(bindings: [KeyBinding], initiallyHeld: Set<UInt16> = []) {
        var map = Dictionary(bindings.map { ($0.source,$0.target) }, uniquingKeysWith: { _,last in last })
        // Physical target keys share ownership with remapped keys (A→C plus real C).
        for binding in bindings {
            if case .key(let code) = binding.target, map[code] == nil { map[code] = .key(code) }
        }
        self.bindings = map; physicalDown = initiallyHeld; ignoredUntilRelease = initiallyHeld
        let targets = Set(map.values.compactMap { action -> UInt16? in if case .key(let key) = action { return key }; return nil })
        // Adopt physical targets held before focus entry without synthesizing another down.
        for source in initiallyHeld where targets.contains(source) {
            held[source] = .key(source); counts[source,default:0] += 1
        }
    }
    func intercepts(_ source: UInt16, down: Bool = true) -> Bool {
        if ignoredUntilRelease.contains(source) {
            return !down && held[source] == .key(source) && counts[source,default:0] > 1
        }
        return bindings[source] != nil
    }
    func maps(_ source: UInt16) -> Bool { bindings[source] != nil }
    func owns(_ source:UInt16) -> Bool { held[source] != nil && !ignoredUntilRelease.contains(source) }
    var usesCapsLock: Bool { bindings[57] != nil || bindings.values.contains(.key(57)) }
    var activeModifiers: [UInt16] { counts.filter { $0.value > 0 && KeyCatalog.modifiers[$0.key] != nil }.map(\.key) }
    func handle(_ source: UInt16, down: Bool, repeating: Bool = false) -> [MappedKeyEvent] {
        transition(source,down:down,repeating:repeating,deliveredTarget:nil)
    }
    /// Karabiner already chose this target. This path only owns balanced PID delivery.
    func deliver(source:UInt16,target:KeyTarget,down:Bool,repeating:Bool = false) -> [MappedKeyEvent] {
        transition(source,down:down,repeating:repeating,deliveredTarget:target)
    }
    private func transition(_ source:UInt16,down:Bool,repeating:Bool,deliveredTarget:KeyTarget?) -> [MappedKeyEvent] {
        let otherKeysWereHeld = !physicalDown.subtracting([source]).isEmpty
        if down { physicalDown.insert(source) } else { physicalDown.remove(source) }
        if ignoredUntilRelease.contains(source) {
            if !down {
                ignoredUntilRelease.remove(source)
                if held.removeValue(forKey:source) != nil {
                    counts[source,default:1] -= 1
                    if counts[source] == 0 { counts.removeValue(forKey:source); order.removeAll { $0 == source } }
                }
            }
            return []
        }
        if down {
            for (key, action) in held where key != source && action == .toggleInputSource { interrupted.insert(key) }
            guard let target = deliveredTarget ?? bindings[source] else { return [] }
            if held[source] != nil {
                if repeating, case .key(let code) = target, code != 57, KeyCatalog.modifiers[code] == nil { return [.down(code)] }
                return []
            }
            held[source] = target
            if target == .toggleInputSource && otherKeysWereHeld { interrupted.insert(source) }
            switch target {
            case .key(57): capsLock.toggle(); return [.caps(capsLock)]
            case .key(let code):
                let count = counts[code, default: 0]; counts[code] = count + 1
                if !order.contains(code) { order.append(code) }
                if count == 0 { return [.down(code)] }
            default: break
            }
        } else if let target = held.removeValue(forKey: source) {
            switch target {
            case .key(let code) where code != 57:
                counts[code, default: 1] -= 1
                if counts[code] == 0 { counts.removeValue(forKey: code); order.removeAll { $0 == code }; return [.up(code)] }
            case .toggleInputSource:
                if interrupted.remove(source) == nil { return [.inputSource] }
            default: break
            }
        }
        return []
    }
    func releaseAll() -> [MappedKeyEvent] {
        let owned = Set(held.filter { !ignoredUntilRelease.contains($0.key) }.values.compactMap { target -> UInt16? in
            if case .key(let code) = target, code != 57 { return code }; return nil
        })
        var events = order.reversed().filter { owned.contains($0) }.map(MappedKeyEvent.up)
        if capsLock { events.append(.caps(false)) }
        held.removeAll(); counts.removeAll(); order.removeAll(); interrupted.removeAll(); physicalDown.removeAll(); ignoredUntilRelease.removeAll(); capsLock = false
        return events
    }
    func rewriteFlags(_ raw: UInt64) -> UInt64 {
        var result = raw
        let affected = Set(bindings.keys.filter { !ignoredUntilRelease.contains($0) }.compactMap { KeyCatalog.modifiers[$0]?.generic })
        for source in bindings.keys where !ignoredUntilRelease.contains(source) {
            if let modifier = KeyCatalog.modifiers[source] { result &= ~modifier.side }
        }
        for generic in affected {
            let sides = KeyCatalog.modifiers.values.filter { $0.generic == generic }.reduce(UInt64(0)) { $0 | $1.side }
            if result & sides == 0 { result &= ~generic }
        }
        for code in activeModifiers {
            let modifier = KeyCatalog.modifiers[code]!; result |= modifier.generic | modifier.side
        }
        if usesCapsLock { result = capsLock ? result | 0x10000 : result & ~UInt64(0x10000) }
        return result
    }
}

enum KeyScope {
    static func matchesEvent(frontmost: Int32, eventTarget: Int64, attested: Int32) -> Bool {
        attested > 0 && frontmost == attested && eventTarget == Int64(attested)
    }
    static func accepts(processExecutable: String, mappedPaths: [String], wrapper: URL) -> Bool {
        guard processExecutable.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0 == "/" || $0 == "\\" }).last?.lowercased() == "dnf.exe" else { return false }
        let prefix = wrapper.appendingPathComponent("Contents/SharedSupport/prefix/drive_c").resolvingSymlinksInPath().path + "/"
        return mappedPaths.contains { raw in
            guard URL(fileURLWithPath:raw).lastPathComponent.lowercased() == "dnf.exe" else { return false }
            let file = URL(fileURLWithPath: raw).resolvingSymlinksInPath()
            return file.lastPathComponent.lowercased() == "dnf.exe" && file.path.hasPrefix(prefix)
        }
    }
}

/// Physical HID and input-source notifications may arrive in either order.
struct KeyInputSourceGuard {
    private var source: String?
    private var previous: String?
    private var changedAt = -Double.infinity
    private var guardUntil = -Double.infinity
    init(source: String?) { self.source = source }
    mutating func sourceChanged(_ id: String, now: TimeInterval) -> String? {
        guard id != source else { return nil }
        if now < guardUntil, let source { return source }
        previous = source; source = id; changedAt = now
        return nil
    }
    mutating func capsDown(now: TimeInterval) -> String? {
        guardUntil = now + 0.7
        if now - changedAt < 0.15, let previous {
            source = previous; self.previous = nil; changedAt = -Double.infinity
            return previous
        }
        return nil
    }
    mutating func intentionalSwitch(_ id: String) {
        source = id; previous = nil; changedAt = -Double.infinity; guardUntil = -Double.infinity
    }
}

/// Delayed self-pause notifications must not stop capture that has already resumed.
enum KeyCaptureLifecycle {
    static func shouldStop(requested: Bool, tapEnabled: Bool) -> Bool { requested && !tapEnabled }
}

/// Repeat belongs to the target PID, never to a held global virtual HID key.
struct KeyRepeatState {
    struct Press { let source:UInt16; let target:KeyTarget; var deadline:TimeInterval }
    let delay:TimeInterval
    let interval:TimeInterval
    private var presses: [Press] = []
    mutating func update(source:UInt16,target:KeyTarget,down:Bool,now:TimeInterval) {
        if !down { presses.removeAll { $0.source == source }; return }
        guard !presses.contains(where: { $0.source == source }),case .key(let code) = target,
              code != 57,KeyCatalog.modifiers[code] == nil else { return }
        presses.append(Press(source:source,target:target,deadline:now+max(0.1,delay)))
    }
    mutating func due(now:TimeInterval) -> Press? {
        guard let last = presses.indices.last,now >= presses[last].deadline else { return nil }
        let press = presses[last]; presses[last].deadline = now+max(0.01,interval); return press
    }
    mutating func clear() { presses.removeAll() }
}

/// Both Karabiner's physical-key verdict and native prior-held-key verdict are
/// required, because raw CGEvents and user-command datagrams have different queues.
struct KeyAloneState {
    private var eligible = Set<UInt16>()
    private var core = Set<UInt16>()
    mutating func begin(_ source:UInt16) { eligible.remove(source); core.remove(source) }
    mutating func nativeVerdict(_ source:UInt16,eligible allowed:Bool) -> Bool {
        guard allowed else { begin(source); return false }
        if core.remove(source) != nil { self.eligible.remove(source); return true }
        eligible.insert(source); return false
    }
    mutating func karabinerVerdict(_ source:UInt16,held:Bool) -> Bool {
        if eligible.remove(source) != nil { core.remove(source); return true }
        if held { core.insert(source) }; return false
    }
    mutating func clear() { eligible.removeAll(); core.removeAll() }
}
