import Foundation
import CryptoKit

/// Pure routing/configuration. This module never receives text or authentication data.
enum KarabinerKeys {
    static func name(_ code: UInt16) -> String? { names[code] }
    private static let names: [UInt16:String] = {
        var map: [UInt16:String] = [55:"left_command",54:"right_command",59:"left_control",62:"right_control",58:"left_option",61:"right_option",56:"left_shift",60:"right_shift",57:"caps_lock",49:"spacebar",36:"return_or_enter",48:"tab",51:"delete_or_backspace",53:"escape",117:"delete_forward",123:"left_arrow",124:"right_arrow",125:"down_arrow",126:"up_arrow",115:"home",119:"end",116:"page_up",121:"page_down",50:"grave_accent_and_tilde",27:"hyphen",24:"equal_sign",33:"open_bracket",30:"close_bracket",42:"backslash",41:"semicolon",39:"quote",43:"comma",47:"period",44:"slash",65:"keypad_period",67:"keypad_asterisk",69:"keypad_plus",75:"keypad_slash",78:"keypad_hyphen",81:"keypad_equal_sign",76:"keypad_enter",71:"keypad_num_lock"]
        for item in KeyCatalog.keys {
            if item.name.count == 1, item.name.first!.isLetter || item.name.first!.isNumber { map[item.code] = item.name.lowercased() }
            if item.name.hasPrefix("F"), Int(item.name.dropFirst()) != nil { map[item.code] = item.name.lowercased() }
            if item.name.hasPrefix("키패드 "), let digit = Int(item.name.dropFirst(4)) { map[item.code] = "keypad_\(digit)" }
        }
        return map
    }()
}

enum KarabinerRule {
    static func token(wrapper: URL) -> String {
        String(SHA256.hash(data:Data(wrapper.standardizedFileURL.resolvingSymlinksInPath().path.utf8)).map { String(format:"%02x",$0) }.joined().prefix(20))
    }
    static func identity(wrapper: URL) -> String { "DNF TUI [\(token(wrapper:wrapper))]" }
    static func variable(wrapper: URL) -> String { "dnf_\(token(wrapper:wrapper))" }
    static let physicalModifiers = ["left_control","right_control","left_option","right_option","left_shift","right_shift","left_command","right_command"]
}

struct KarabinerConfigStore {
    let file: URL
    var backup: URL { file.deletingLastPathComponent().appendingPathComponent("karabiner.before-dnf-tui.json") }
    func revision() throws -> Data {
        let values = try file.resourceValues(forKeys:[.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw KeyMappingError(message:"karabiner.json 파일 자체가 심볼릭 링크입니다. 원본 설정 위치를 확인해 주세요.") }
        let data = try Data(contentsOf:file)
        guard data.count <= 4*1024*1024 else { throw KeyMappingError(message:"Karabiner 설정 파일이 너무 큽니다.") }
        return data
    }
    func install(rule:[String:Any],identity:String,expectedRevision:Data) throws {
        try mutate(identity:identity,rule:rule,expected:expectedRevision)
    }
    func remove(identity:String) throws { try mutate(identity:identity,rule:nil,expected:revision()) }
    private func mutate(identity:String,rule:[String:Any]?,expected:Data) throws {
        guard try revision() == expected else { throw KeyMappingError(message:"Karabiner 설정이 다른 곳에서 변경됐습니다. 다시 시도해 주세요.") }
        guard var config = try JSONSerialization.jsonObject(with:expected) as? [String:Any], var profiles = config["profiles"] as? [[String:Any]],
              profiles.filter({ $0["selected"] as? Bool == true }).count == 1 else { throw KeyMappingError(message:"Karabiner의 현재 프로필을 확인할 수 없습니다.") }
        for index in profiles.indices {
            var complex = profiles[index]["complex_modifications"] as? [String:Any] ?? [:]
            var rules = complex["rules"] as? [[String:Any]] ?? []
            let oldCount = rules.count
            rules.removeAll { $0["description"] as? String == identity }
            if profiles[index]["selected"] as? Bool == true, let rule { rules.insert(rule,at:0) }
            if rules.count != oldCount || (profiles[index]["selected"] as? Bool == true && rule != nil) {
                complex["rules"] = rules; profiles[index]["complex_modifications"] = complex
            }
        }
        config["profiles"] = profiles
        let output = try JSONSerialization.data(withJSONObject:config,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
        // Byte-level snapshot is retained once; restore removes only our current rule.
        if !FileManager.default.fileExists(atPath:backup.path) { try expected.write(to:backup,options:.withoutOverwriting); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:backup.path) }
        guard try revision() == expected else { throw KeyMappingError(message:"Karabiner 설정이 저장 중 변경됐습니다. 다시 시도해 주세요.") }
        let permissions = (try FileManager.default.attributesOfItem(atPath:file.path))[.posixPermissions] as? NSNumber
        try output.write(to:file,options:.atomic)
        if let permissions { try FileManager.default.setAttributes([.posixPermissions:permissions],ofItemAtPath:file.path) }
    }
}

struct KarabinerLease {
    private(set) var generation: UInt64 = 0
    struct Grant: Equatable { let issued: Int64; let expires: Int64 }
    @discardableResult mutating func invalidate() -> UInt64 { generation &+= 1; return generation }
    func issue(generation: UInt64, now: Int64, attested: Bool) -> Grant? {
        guard generation == self.generation,attested else { return nil }
        return Grant(issued:now,expires:now+500)
    }
}

enum KarabinerAvailability {
    static func supports(version:String) -> Bool {
        let numbers = version.trimmingCharacters(in:.whitespacesAndNewlines).split(separator:".").compactMap { Int($0) }
        guard numbers.count >= 2 else { return false }
        return numbers[0] > 16 || (numbers[0] == 16 && numbers[1] >= 3)
    }
    static func conflictingSources(profile:[String:Any],sources:Set<String>) -> Set<String> {
        let containers = [profile] + (profile["devices"] as? [[String:Any]] ?? [])
        return Set(containers.flatMap { ($0["simple_modifications"] as? [[String:Any]] ?? []).compactMap { ($0["from"] as? [String:String])?["key_code"] } }).intersection(sources)
    }
}

struct KarabinerAcknowledgments {
    private var pending: (UInt64,TimeInterval)?
    mutating func begin(sequence:UInt64,now:TimeInterval) -> Bool {
        guard pending == nil else { return false }; pending = (sequence,now); return true
    }
    mutating func acknowledge(sequence:UInt64) -> Bool {
        guard pending?.0 == sequence else { return false }; pending = nil; return true
    }
    func expired(now:TimeInterval) -> Bool { pending.map { now-$0.1 > 0.3 } ?? false }
    var waiting: Bool { pending != nil }
}
