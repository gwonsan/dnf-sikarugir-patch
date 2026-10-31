import CoreGraphics
import Foundation

private func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fputs("FAIL: \(message)\n",stderr); exit(1) }
}

@main struct KeyEventDeliveryTests {
    static func main() {
        let state = KeyMappingState(bindings:[.init(source:0,target:.key(11))])
        var repeatState = KeyRepeatState(delay:0.5,interval:0.08)
        expect(state.deliver(source:0,target:.key(11),down:true) == [.down(11)], "initial semantic down owns B")
        repeatState.update(source:0,target:.key(11),down:state.owns(0),now:0)
        let press = repeatState.due(now:0.6)!
        let outputs = state.deliver(source:press.source,target:press.target,down:true,repeating:true)
        expect(outputs == [.down(11)], "scheduled repeat produces another B down without releasing hold")
        let event = KeyEventDelivery.make(key:11,down:true,flags:0,marker:713,repeating:true)!
        expect(event.type == .keyDown, "scheduled delivery remains a key down")
        expect(event.getIntegerValueField(.keyboardEventAutorepeat) == 0, "PID-only repeats must use ordinary downs; flagged synthetic repeats are ignored by the real game")
        expect(event.getIntegerValueField(.keyboardEventKeycode) == 11, "target key survives delivery")
        expect(event.getIntegerValueField(.eventSourceUserData) == 713, "owned event bypass marker survives delivery")
        expect(state.deliver(source:0,target:.key(11),down:false) == [.up(11)], "one physical release balances the held target")
        expect(state.releaseAll().isEmpty, "balanced release leaves no owned key")
        let modifier = KeyEventDelivery.make(key:59,down:true,flags:0x40001,marker:713)!
        expect(modifier.type == .flagsChanged && modifier.flags.rawValue == 0x40001, "modifier retains flagsChanged and flags")
        expect(KeyEventDelivery.make(key:57,down:false,flags:0,marker:713)?.type == .flagsChanged, "Caps keeps its flagsChanged representation")
        expect(KeyEventDelivery.make(key:11,down:false,flags:0,marker:713)?.type == .keyUp, "ordinary release remains a key up")
        let shortcut = KeyInputSourceShortcut.previous(configuration:nil)!
        let strokes = shortcut.strokes(baseFlags:0x10000)
        expect(strokes.map(\.key) == [59,49,49,59], "system default previous-source shortcut is a balanced Control-Space chord")
        expect(strokes.map(\.down) == [true,true,false,false], "shortcut always releases its key and modifier")
        expect(strokes.last?.flags == 0x10000, "shortcut restores the prior virtual Caps flag")
        let custom:[String:Any] = ["60":["enabled":true,"value":["type":"standard","parameters":[65535,80,1179648]]]]
        expect(KeyInputSourceShortcut.previous(configuration:custom)?.strokes(baseFlags:0).map(\.key) == [56,55,80,80,55,56], "custom Shift-Command F19 honors current macOS shortcut")
        expect(KeyInputSourceShortcut.previous(configuration:["60":["enabled":false]]) == nil, "disabled system shortcut never injects ordinary text")
        expect(KeyInputSourceShortcut.previous(configuration:["60":"invalid"]) == nil, "malformed configured entry must not silently use a default shortcut")
        expect(KeyInputSourceShortcut.previous(configuration:["60":["enabled":true,"value":["type":"standard","parameters":[32,999,262144]]]]) == nil, "malformed shortcut key fails closed")
        expect(KeyInputSourceShortcut.previous(configuration:["60":["enabled":true,"value":["type":"standard","parameters":[32,49,8388608]]]]) == nil, "unsupported modifier flags fail closed")
        print("PASS: PID delivery metadata, repeated downs, held ownership and balanced release")
    }
}
