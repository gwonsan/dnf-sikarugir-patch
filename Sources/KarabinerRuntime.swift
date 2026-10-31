import Foundation

/// A single bounded acknowledged CLI connection. All state is accessed on the main run loop.
/// Receives ephemeral semantic commands; never records input events or text.
final class KarabinerRuntime {
    static let cli = URL(fileURLWithPath:"/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli")
    static var configuration: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath:$0) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base.appendingPathComponent("karabiner/karabiner.json")
    }
    static var installedVersion: String? {
        (NSDictionary(contentsOf:URL(fileURLWithPath:"/Applications/Karabiner-Elements.app/Contents/Info.plist"))?["CFBundleShortVersionString"] as? String)
    }
    static var detection: String {
        guard let version = installedVersion, FileManager.default.isExecutableFile(atPath:cli.path) else { return "Karabiner 없음 · 자체 매핑 사용" }
        return KarabinerAvailability.supports(version:version) ? "Karabiner \(version) 감지 · 게임 실행 시 연결 확인" : "Karabiner \(version) · 16.3 이상 필요"
    }
    let bindings: [KeyBinding]
    private let profile: KeyProfile
    private var socket: KarabinerSocket?
    private var session: String?
    private var generation: Int64 = 0
    private let wrapper: URL
    private let store: KarabinerConfigStore
    private let variable: String
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private var buffer = Data()
    private var acknowledgments = KarabinerAcknowledgments()
    private var sequence: UInt64 = 0
    private var acknowledged = false
    private var submittedActive = false
    private var authorized = false
    private struct Grant {
        let wall:Int64
        let uptime:TimeInterval
        static var now:Grant {
            let uptime = ProcessInfo.processInfo.systemUptime
            return Grant(wall:Int64(Date().timeIntervalSince1970*1000),uptime:uptime)
        }
        func live(at now:Grant) -> Bool {
            now.uptime >= uptime && now.uptime-uptime < 0.5 && now.wall >= wall && now.wall-wall < 500
        }
    }
    private var activeGrant:Grant?
    private var pendingGrant:(generation:Int64,grant:Grant)?
    private var failed = false
    private var installedRevision: Data?
    private var checkedConfiguration = Date.distantPast
    private(set) var failureMessage = "Karabiner 연결 중단 · TUI에서 다시 시작해 주세요."
    var healthy: Bool {
        let now = Grant.now
        if let grant = activeGrant,!grant.live(at:now) { return false }
        return !failed && process.isRunning && !acknowledgments.expired(now:now.uptime)
    }

    init(profile:KeyProfile,wrapper:URL,configuration:URL = KarabinerRuntime.configuration,cli:URL = KarabinerRuntime.cli,version:String? = KarabinerRuntime.installedVersion) throws {
        self.wrapper = wrapper; self.profile = profile; bindings = KarabinerDeliveryRule.effectiveBindings(profile:profile)
        store = KarabinerConfigStore(file:configuration); variable = KarabinerRule.variable(wrapper:wrapper)
        guard let version, KarabinerAvailability.supports(version:version), FileManager.default.isExecutableFile(atPath:cli.path) else { throw KeyMappingError(message:Self.detection) }
        let data = try store.revision()
        guard let config = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let selected = (config["profiles"] as? [[String:Any]])?.first(where: { $0["selected"] as? Bool == true }) else { throw KeyMappingError(message:"Karabiner 프로필을 찾을 수 없습니다.") }
        let sources = Set(bindings.compactMap { KarabinerKeys.name($0.source) }).union(["left_control","right_control","left_option","right_option","escape"])
        let conflicts = KarabinerAvailability.conflictingSources(profile:selected,sources:sources)
        guard conflicts.isEmpty else { throw KeyMappingError(message:"Karabiner Simple Modifications 충돌: \(conflicts.sorted().joined(separator:", ")). 기존 설정을 확인해 주세요.") }
        process.executableURL = cli; process.arguments = ["--set-variables-from-stdin","--verbose"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.received(data) }
        }
        do {
            try process.run(); submit(active:false)
            let deadline = Date(timeIntervalSinceNow:1.5)
            while !acknowledged && !failed && process.isRunning && Date() < deadline { _ = RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.02)) }
            guard acknowledged else { throw KeyMappingError(message:"Karabiner가 응답하지 않습니다. 실행 상태와 권한을 확인해 주세요.") }
            let executable = wrapper.appendingPathComponent("Contents/SharedSupport/wine/lib/wine/x86_64-unix/wine")
            guard FileManager.default.isExecutableFile(atPath:executable.path) else { throw KeyMappingError(message:"던파 전용 Wine 실행 파일을 찾을 수 없습니다.") }
            // A previous crashed session is inactive; never retain its input endpoint.
            try store.remove(identity:KarabinerRule.identity(wrapper:wrapper))
            installedRevision = try store.revision()
        } catch { close(removeRule:false); throw error }
    }
    private func received(_ data:Data) {
        guard !data.isEmpty, buffer.count+data.count <= 65536 else { failed = true; return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of:10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with:line) as? [String:Any],
                  let value = object[variable+"_sequence"] as? NSNumber else { continue }
            let continuous = healthy
            if acknowledgments.acknowledge(sequence:value.uint64Value) {
                guard continuous else { failed = true; return }
                acknowledged = true
                if submittedActive {
                    guard let pending = pendingGrant else { failed = true; return }
                    pendingGrant = nil
                    // An invalidated generation's ACK cannot arm a newer focus.
                    guard authorized,pending.generation == generation else {
                        activeGrant = nil; submit(active:false); continue
                    }
                    let now = Grant.now
                    guard pending.grant.live(at:now),activeGrant?.live(at:now) ?? true else { failed = true; return }
                    // Keep the previous confirmed expiry until its replacement
                    // is acknowledged, including any main-loop or CLI delay.
                    activeGrant = pending.grant
                } else { activeGrant = nil; pendingGrant = nil }
            }
        }
    }
    private func submit(active:Bool) {
        guard !failed,process.isRunning,!acknowledgments.waiting else { return }
        let now = Grant.now
        // Recheck after potentially blocking configuration reads. A new write
        // must never hide an expiry that occurred after renew's first check.
        if active,let grant = activeGrant,!grant.live(at:now) { failed = true; return }
        sequence &+= 1
        guard acknowledgments.begin(sequence:sequence,now:now.uptime) else { return }
        submittedActive = active
        pendingGrant = active ? (generation,now) : nil
        if !active { activeGrant = nil }
        var values:[String:Any] = [variable+"_generation":generation,variable+"_sequence":sequence,variable+"_active":active ? 1 : 0,variable+"_issued":now.wall,variable+"_expires":active ? now.wall+500 : 0]
        if !active { for name in KarabinerRule.physicalModifiers { values[variable+"_physical_"+name] = 0 } }
        do { var data = try JSONSerialization.data(withJSONObject:values,options:.sortedKeys); data.append(10); try input.fileHandleForWriting.write(contentsOf:data) }
        catch { failed = true }
    }
    func beginSession(receive:@escaping(KarabinerDeliveryMessage)->Void) throws {
        invalidate()
        guard healthy, let revision = installedRevision else { throw KeyMappingError(message:failureMessage) }
        let token = UUID().uuidString
        generation = Int64.random(in:1..<(1<<48))
        let expected = Dictionary(bindings.map { ($0.source,$0.target) },uniquingKeysWith:{ _,last in last })
        let receiver = try KarabinerSocket { [weak self] data in
            guard let self, self.authorized, self.activeGrant != nil, self.healthy, self.session == token,
                  let message = try? JSONDecoder().decode(KarabinerDeliveryMessage.self,from:data), message.session == token else { return }
            if message.emergency {
                guard message.source == 53, message.target == .disabled, message.down else { return }
            } else {
                guard expected[message.source] == message.target,
                      !message.alone || (message.target == .toggleInputSource && !message.down) else { return }
            }
            receive(message)
        }
        socket = receiver; session = token
        do {
            let executable = wrapper.appendingPathComponent("Contents/SharedSupport/wine/lib/wine/x86_64-unix/wine")
            let rule = try KarabinerDeliveryRule.make(profile:profile,wineExecutable:executable,endpoint:receiver.endpoint,session:token,generation:generation)
            try store.install(rule:rule,identity:KarabinerRule.identity(wrapper:wrapper),expectedRevision:revision)
            installedRevision = try store.revision(); checkedConfiguration = Date()
        } catch { invalidate(); throw error }
    }
    func invalidate() {
        authorized = false; activeGrant = nil; submit(active:false)
        // Queued old commands cannot cross a foreground generation: its socket is gone.
        socket?.close(); socket = nil; session = nil
    }
    func renew(attested:Bool) {
        authorized = attested && socket != nil
        guard healthy else { failed = true; return }
        if Date().timeIntervalSince(checkedConfiguration) > 1 {
            checkedConfiguration = Date()
            guard let data = try? store.revision(), data == installedRevision else {
                failureMessage = "Karabiner 설정이 변경되어 매핑을 중지했습니다. TUI에서 S로 다시 시작해 주세요."
                invalidate(); failed = true; return
            }
        }
        submit(active:authorized)
    }
    func close(removeRule:Bool = true) {
        invalidate()
        if process.isRunning {
            // Even when an old grant is in flight, its absolute expiry remains <= 500ms.
            if !failed { submit(active:false) }
            try? input.fileHandleForWriting.close()
            process.terminate()
        }
        output.fileHandleForReading.readabilityHandler = nil
        if removeRule, installedRevision != nil { try? store.remove(identity:KarabinerRule.identity(wrapper:wrapper)) }
        installedRevision = nil
    }
    deinit { close() }
}
