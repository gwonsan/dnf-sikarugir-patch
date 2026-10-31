import Foundation

/// Karabiner chooses the semantic target; the receiver only completes delivery to DNF.
struct KarabinerDeliveryMessage: Codable, Equatable {
    let session: String
    let source: UInt16
    let target: KeyTarget
    let down: Bool
    var emergency = false
    var alone = false
}

enum KarabinerDeliveryRule {
    private static let modifierCodes: [UInt16] = [55, 54, 59, 62, 58, 61, 56, 60]

    static func effectiveBindings(profile: KeyProfile) -> [KeyBinding] {
        var bindings = profile.bindings
        var sources = Set(bindings.map(\.source))
        // Keep modifiers and ordinary keys on the same ordered channel. Mixing
        // socket modifiers with raw letter events loses rapid Shift/Control chords.
        // Explicit choices still win; identities also provide shared target ownership.
        for key in KeyCatalog.keys where sources.insert(key.code).inserted {
            bindings.append(.init(source:key.code,target:.key(key.code)))
        }
        return bindings
    }

    static func make(profile: KeyProfile, wineExecutable: URL, endpoint: String, session: String, generation: Int64) throws -> [String: Any] {
        try profile.validate()
        let wrapper = URL(fileURLWithPath: profile.wrapperPath)
        let prefix = KarabinerRule.variable(wrapper: wrapper)
        // Karabiner's regex parser requires explicit escaping of a literal closing ].
        let metacharacters = Set("\\.^$|?*+()[]{}")
        let path = wineExecutable.standardizedFileURL.resolvingSymlinksInPath().path.map {
            metacharacters.contains($0) ? "\\" + String($0) : String($0)
        }.joined()
        let conditions: [[String: Any]] = [
            ["type": "frontmost_application_if", "file_paths": ["^\(path)$"]],
            ["type": "expression_if", "expression": "\(prefix)_active == 1 and \(prefix)_issued <= system.now.milliseconds and system.now.milliseconds < \(prefix)_expires and \(prefix)_generation == \(generation)"]
        ]
        func command(source: UInt16, target: KeyTarget, down: Bool, emergency: Bool = false, alone:Bool = false, scoped: [[String: Any]]) throws -> [String: Any] {
            let message = KarabinerDeliveryMessage(session: session, source: source, target: target, down: down, emergency: emergency, alone:alone)
            let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(message))
            return ["send_user_command": ["endpoint": endpoint, "payload": payload], "conditions": scoped]
        }
        func from(_ name: String) -> [String: Any] {
            ["key_code": name, "modifiers": ["optional": ["any"]]]
        }
        // from.modifiers sees transformed state. Physical variables preserve this chord
        // even when Control or Option has a different semantic target.
        let emergencyConditions = conditions + [[
            "type": "expression_if",
            "expression": "(\(prefix)_physical_left_control == 1 or \(prefix)_physical_right_control == 1) and (\(prefix)_physical_left_option == 1 or \(prefix)_physical_right_option == 1)"
        ]]
        var manipulators: [[String: Any]] = [[
            "type": "basic", "from": from("escape"), "conditions": emergencyConditions,
            "to": [try command(source: 53, target: .disabled, down: true, emergency: true, scoped: emergencyConditions)]
        ]]
        for binding in effectiveBindings(profile: profile) {
            guard let source = KarabinerKeys.name(binding.source) else {
                throw KeyMappingError(message: "Karabiner에서 지원하지 않는 입력 키입니다.")
            }
            var down = [try command(source: binding.source, target: binding.target, down: true, scoped: conditions)]
            var up = [try command(source: binding.source, target: binding.target, down: false, scoped: conditions)]
            if modifierCodes.contains(binding.source) {
                let name = prefix + "_physical_" + source
                down.insert(["set_variable": ["name": name, "value": 1], "conditions": conditions], at: 0)
                up.insert(["set_variable": ["name": name, "value": 0], "conditions": conditions], at: 0)
            }
            var item: [String:Any] = ["type":"basic","from":from(source),"conditions":conditions,"to":down,"to_after_key_up":up]
            if binding.target == .toggleInputSource {
                item["to_if_alone"] = [try command(source:binding.source,target:binding.target,down:false,alone:true,scoped:conditions)]
            }
            manipulators.append(item)
        }
        return ["description": KarabinerRule.identity(wrapper: wrapper), "manipulators": manipulators]
    }
}
