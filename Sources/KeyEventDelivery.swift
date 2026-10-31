import CoreGraphics
import Foundation

enum KeyEventDelivery {
    static func make(key:UInt16,down:Bool,flags:UInt64,marker:Int64,repeating _:Bool = false) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource:nil,virtualKey:CGKeyCode(key),keyDown:down) else { return nil }
        if KeyCatalog.modifiers[key] != nil || key == 57 { event.type = .flagsChanged }
        event.flags = CGEventFlags(rawValue:flags)
        // These events bypass the global keyboard's held-key state. Marked
        // synthetic repeats are ignored in DNF; ordinary repeated downs work.
        // Logical repeat timing and the final balanced release remain owned by
        // KeyMappingState/KeyRepeatState, without tapping the key between repeats.
        event.setIntegerValueField(.keyboardEventAutorepeat,value:0)
        event.setIntegerValueField(.eventSourceUserData,value:marker)
        return event
    }
}

/// Read the user's existing previous-input-source shortcut; never change it.
struct KeyInputSourceShortcut {
    struct Stroke { let key:UInt16; let down:Bool; let flags:UInt64 }
    private let key:UInt16
    private let modifiers:[UInt16]

    static func previous(configuration:[String:Any]?) -> KeyInputSourceShortcut? {
        let key:Int, flags:UInt64
        if let raw = configuration?["60"] {
            guard let entry = raw as? [String:Any],entry["enabled"] as? Bool == true,
                  let value = entry["value"] as? [String:Any], value["type"] as? String == "standard",
                  let parameters = value["parameters"] as? [Int], parameters.count == 3,
                  parameters[2] >= 0 else { return nil }
            key = parameters[1]; flags = UInt64(parameters[2])
        } else { key = 49; flags = 0x40000 }
        guard let code = UInt16(exactly:key), KeyCatalog.keys.contains(where:{$0.code == code}),
              KeyCatalog.modifiers[code] == nil, code != 57, flags & ~UInt64(0x1e0000) == 0 else { return nil }
        let modifiers:[UInt16] = [59,58,56,55].filter { flags & KeyCatalog.modifiers[$0]!.generic != 0 }
        return KeyInputSourceShortcut(key:code,modifiers:modifiers)
    }

    func strokes(baseFlags:UInt64) -> [Stroke] {
        var flags = baseFlags, result:[Stroke] = []
        for code in modifiers {
            let modifier = KeyCatalog.modifiers[code]!
            flags |= modifier.side | modifier.generic
            result.append(Stroke(key:code,down:true,flags:flags))
        }
        result.append(Stroke(key:key,down:true,flags:flags))
        result.append(Stroke(key:key,down:false,flags:flags))
        for code in modifiers.reversed() {
            let modifier = KeyCatalog.modifiers[code]!
            flags &= ~modifier.side
            let sides = KeyCatalog.modifiers.values.filter{$0.generic == modifier.generic}.reduce(UInt64(0)){$0 | $1.side}
            if flags & sides == 0 { flags &= ~modifier.generic }
            flags |= baseFlags
            result.append(Stroke(key:code,down:false,flags:flags))
        }
        return result
    }
}
