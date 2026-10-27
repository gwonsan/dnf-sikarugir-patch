import Foundation
import AppKit
import CoreGraphics

final class Probe {
    var tap: CFMachPort?
    var requested = false
    var stops = 0
    var notifications = 0
}
@main struct EventTapLifecycleTests {
    static func main() {
        let app=NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
        let probe=Probe()
        guard let tap=CGEvent.tapCreate(tap:.cgAnnotatedSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:1 << CGEventType.mouseMoved.rawValue,callback:{_,type,event,context in
            if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout, let context {
                let p=Unmanaged<Probe>.fromOpaque(context).takeUnretainedValue()
                p.notifications += 1
                if KeyCaptureLifecycle.shouldStop(requested:p.requested,tapEnabled:p.tap.map { CGEvent.tapIsEnabled(tap:$0) } ?? false) { p.stops += 1 }
            }
            return Unmanaged.passUnretained(event)
        },userInfo:Unmanaged.passUnretained(probe).toOpaque()) else {
            print("SKIP: native mouse-only tap unavailable (no permission requested)"); return
        }
        probe.tap=tap
        let source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
        CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
        defer { CFMachPortInvalidate(tap) }
        func drain() { RunLoop.current.run(until:Date(timeIntervalSinceNow:0.15)) }
        func expect(_ value:Bool,_ message:String) { if !value { fputs("FAIL: \(message)\n",stderr);exit(1) } }
        CGEvent.tapEnable(tap:tap,enable:false); drain()
        expect(probe.notifications > 0,"native intentional pause emits a disable notification")
        expect(probe.stops == 0,"initial intentional pause preserves agent")
        CGEvent.tapEnable(tap:tap,enable:true); probe.requested=true
        probe.requested=false; CGEvent.tapEnable(tap:tap,enable:false)
        probe.requested=true; CGEvent.tapEnable(tap:tap,enable:true); drain()
        expect(probe.stops == 0,"queued pause after re-enable must not stop active capture")
        CGEvent.tapEnable(tap:tap,enable:false); drain()
        expect(probe.stops == 1,"unexpected active capture disable still stops the agent")
        print("PASS: native pause, pause/resume notification race and unexpected active stop")
    }
}
