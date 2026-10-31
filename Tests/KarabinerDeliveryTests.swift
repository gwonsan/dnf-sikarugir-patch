import Foundation

private func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct KarabinerDeliveryTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("delivery tests \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let wrapper = root.appendingPathComponent("Apps [1]+(old)/DNF.app")
        let wine = wrapper.appendingPathComponent("Contents/SharedSupport/wine/lib/wine/x86_64-unix/wine")
        var profile = KeyProfile(wrapperPath: wrapper.path)
        profile.enabled = true
        profile.bindings = [
            .init(source: 0, target: .key(11)), .init(source: 11, target: .key(0)),
            .init(source: 8, target: .key(2)), .init(source: 3, target: .disabled),
            .init(source: 61, target: .toggleInputSource), .init(source: 59, target: .key(49))
        ]
        let effective = KarabinerDeliveryRule.effectiveBindings(profile: profile)
        check(effective.filter { $0.source == 0 } == [.init(source: 0, target: .key(11))], "swap preserves explicit A target B")
        check(effective.filter { $0.source == 11 } == [.init(source: 11, target: .key(0))], "swap preserves explicit B target A")
        check(effective.contains(.init(source: 2, target: .key(2))), "unbound target D is adopted for shared ownership")
        check(Set(effective.map(\.source)) == Set(KeyCatalog.keys.map(\.code)), "every catalog key shares one ordered transport with modifier events")
        let modifierCodes: [UInt16] = [55, 54, 59, 62, 58, 61, 56, 60]
        check(modifierCodes.allSatisfy { code in effective.filter { $0.source == code }.count == 1 }, "all eight physical modifiers have a single semantic binding")
        check(effective.first { $0.source == 59 }?.target == .key(49), "implicit modifier identity never overrides explicit Control mapping")
        check(effective.first { $0.source == 61 }?.target == .toggleInputSource, "implicit modifier identity never overrides language switch")
        var caps = profile
        caps.bindings = [.init(source: 0, target: .key(57))]
        check(KarabinerDeliveryRule.effectiveBindings(profile: caps).contains(.init(source: 57, target: .key(57))), "physical Caps is adopted when it is a semantic target")
        caps.bindings.append(.init(source: 57, target: .disabled))
        check(KarabinerDeliveryRule.effectiveBindings(profile: caps).filter { $0.source == 57 } == [.init(source: 57, target: .disabled)], "Caps adoption preserves explicit disabled source")

        let endpoint = root.appendingPathComponent("private.sock").path
        let rule = try KarabinerDeliveryRule.make(profile: profile, wineExecutable: wine, endpoint: endpoint, session: "fresh-session", generation: 713)
        check(rule["description"] as? String == KarabinerRule.identity(wrapper: wrapper), "semantic delivery retains owned rule identity")
        let manipulators = rule["manipulators"] as! [[String: Any]]
        let prefix = KarabinerRule.variable(wrapper: wrapper)
        let escapedPath = "^" + wine.path.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]").replacingOccurrences(of: "+", with: "\\+").replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)").replacingOccurrences(of: ".", with: "\\.") + "$"
        func assertScope(_ conditions: [[String: Any]], _ context: String) {
            check(conditions.contains { $0["type"] as? String == "frontmost_application_if" && $0["file_paths"] as? [String] == [escapedPath] }, "\(context) has exact escaped Wine scope")
            check(conditions.contains { condition in
                guard condition["type"] as? String == "expression_if", let expression = condition["expression"] as? String else { return false }
                return expression.contains("\(prefix)_active == 1") && expression.contains("\(prefix)_issued <= system.now.milliseconds") && expression.contains("system.now.milliseconds < \(prefix)_expires") && expression.contains("\(prefix)_generation == 713") && expression.contains(" and ") && !expression.contains("&&")
            }, "\(context) rechecks active lease and exact session generation")
        }
        func message(_ action: [String: Any]) throws -> KarabinerDeliveryMessage? {
            guard let command = action["send_user_command"] as? [String: Any] else { return nil }
            check(command["endpoint"] as? String == endpoint, "every command uses the private endpoint")
            return try JSONDecoder().decode(KarabinerDeliveryMessage.self, from: JSONSerialization.data(withJSONObject: command["payload"]!))
        }
        let emergency = manipulators[0]
        check((emergency["from"] as? [String: Any])?["key_code"] as? String == "escape", "physical emergency has first priority")
        let emergencyConditions = emergency["conditions"] as! [[String: Any]]
        check(emergencyConditions.contains { condition in
            let expression = condition["expression"] as? String ?? ""
            return expression.contains("\(prefix)_physical_left_control == 1 or \(prefix)_physical_right_control == 1") && expression.contains("\(prefix)_physical_left_option == 1 or \(prefix)_physical_right_option == 1")
        }, "emergency uses physical Control and Option even after their targets change")
        let emergencyMessage = try message((emergency["to"] as! [[String: Any]])[0])
        check(emergencyMessage == .init(session: "fresh-session", source: 53, target: .disabled, down: true, emergency: true), "emergency sends a typed stop command")

        check(manipulators.count == effective.count + 1, "one semantic manipulator owns each effective source plus emergency")
        for manipulator in manipulators {
            assertScope(manipulator["conditions"] as! [[String: Any]], "manipulator")
            let from = manipulator["from"] as! [String: Any]
            check((from["modifiers"] as? [String: [String]])?["optional"] == ["any"], "every physical source accepts held modifiers")
            for group in ["to", "to_after_key_up", "to_if_alone"] {
                for action in manipulator[group] as? [[String: Any]] ?? [] {
                    check(action["key_code"] == nil && action["select_input_source"] == nil && action["shell_command"] == nil, "delivery never holds a global virtual key or invokes per-key shell/TIS")
                    assertScope(action["conditions"] as! [[String: Any]], "action including delayed keyup")
                }
            }
        }
        for binding in effective {
            let keyName = KarabinerKeys.name(binding.source)!
            let manipulator = manipulators.dropFirst().first { ($0["from"] as? [String: Any])?["key_code"] as? String == keyName }!
            let downActions = manipulator["to"] as! [[String: Any]]
            let upActions = manipulator["to_after_key_up"] as! [[String: Any]]
            let downMessages = try downActions.compactMap(message)
            let upMessages = try upActions.compactMap(message)
            check(downMessages == [.init(session: "fresh-session", source: binding.source, target: binding.target, down: true)], "Karabiner chooses semantic target on down, including swaps and language toggle")
            check(upMessages == [.init(session: "fresh-session", source: binding.source, target: binding.target, down: false)], "keyup retains original semantic target and session")
            if modifierCodes.contains(binding.source) {
                check(downActions.contains { ($0["set_variable"] as? [String: Any])?["name"] as? String == prefix + "_physical_" + keyName && ($0["set_variable"] as? [String: Any])?["value"] as? Int == 1 }, "physical modifier down is tracked before substitution")
                check(upActions.contains { ($0["set_variable"] as? [String: Any])?["name"] as? String == prefix + "_physical_" + keyName && ($0["set_variable"] as? [String: Any])?["value"] as? Int == 0 }, "physical modifier up clears tracking")
            }
        }
        let language = manipulators.first { (($0["from"] as? [String:Any])?["key_code"] as? String) == "right_option" }!
        check((language["to_if_alone"] as? [[String:Any]])?.contains { $0["send_user_command"] != nil } == true,"physical standalone verdict comes from Karabiner, avoiding raw-event/socket scheduling races")
        let cli = URL(fileURLWithPath: "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli")
        if FileManager.default.isExecutableFile(atPath: cli.path) {
            let fixture = root.appendingPathComponent("lint.json")
            try JSONSerialization.data(withJSONObject: ["title": "DNF semantic delivery tests", "rules": [rule]], options: [.prettyPrinted, .sortedKeys]).write(to: fixture)
            let process = Process(); process.executableURL = cli
            process.arguments = ["--lint-complex-modifications", fixture.path]
            try process.run(); process.waitUntilExit()
            check(process.terminationStatus == 0, "installed Karabiner parses semantic endpoint, payload, regex, expressions and delayed scope")
        }
        print("PASS: semantic target delivery, ownership adoption, all physical modifiers, scoped emergency and stale generation isolation")
    }
}
