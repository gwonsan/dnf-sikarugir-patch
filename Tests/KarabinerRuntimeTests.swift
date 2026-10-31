import Foundation
import Darwin
func assertRuntime(_ value:@autoclosure ()->Bool,_ message:String) { if !value() { fputs("FAIL: \(message)\n",stderr);exit(1) } }
private func sendRuntime(_ data:Data,to endpoint:String) -> Int {
 let fd = socket(AF_UNIX,SOCK_DGRAM,0); guard fd >= 0 else { return -1 }; defer { Darwin.close(fd) }
 var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX); address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
 let path = Array(endpoint.utf8CString)
 withUnsafeMutableBytes(of:&address.sun_path) { $0.copyBytes(from:path.map { UInt8(bitPattern:$0) }) }
 return withUnsafePointer(to:&address) { ptr in ptr.withMemoryRebound(to:sockaddr.self,capacity:1) { address in data.withUnsafeBytes { sendto(fd,$0.baseAddress,$0.count,0,address,socklen_t(MemoryLayout<sockaddr_un>.size)) } } }
}
private func runtimeCommand(_ file:URL) throws -> (String,Data) {
 let config = try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any]
 let profile = (config["profiles"] as! [[String:Any]])[0]
 let rule = ((profile["complex_modifications"] as! [String:Any])["rules"] as! [[String:Any]])[0]
 for item in rule["manipulators"] as! [[String:Any]] {
  for action in item["to"] as? [[String:Any]] ?? [] {
   if let command = action["send_user_command"] as? [String:Any],let payload = command["payload"] as? [String:Any],payload["source"] as? Int == 57 {
    return (command["endpoint"] as! String,try JSONSerialization.data(withJSONObject:payload))
   }
  }
 }
 throw KeyMappingError(message:"fixture missing semantic command")
}
private func armRuntime(_ runtime:KarabinerRuntime) {
 // Drain the initial inactive acknowledgement, then submit/ack an active grant.
 for _ in 0..<2 {
  runtime.renew(attested:true)
  let deadline = Date(timeIntervalSinceNow:0.1)
  while Date() < deadline { _ = RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.005)) }
 }
}
@main struct KarabinerRuntimeTests {
 static func main() throws {
  assertRuntime(KarabinerAvailability.supports(version:"16.3.0"),"current installed version supported")
  assertRuntime(!KarabinerAvailability.supports(version:"16.1.9"),"old Karabiner cannot use the supported delivery transport")
  assertRuntime(!KarabinerAvailability.supports(version:"16.2.0"),"delivery transport requires verified16.3 floor")
  assertRuntime(!KarabinerAvailability.supports(version:"nonsense"),"invalid versions cannot enable delegation")
  var flow = KarabinerAcknowledgments()
  assertRuntime(flow.begin(sequence:1,now:10),"first command admitted")
  assertRuntime(!flow.begin(sequence:2,now:10.1),"only one in-flight command")
  assertRuntime(!flow.acknowledge(sequence:9),"wrong acknowledgment cannot arm mapping")
  assertRuntime(flow.expired(now:10.4),"silent CLI cannot remain healthy")
  assertRuntime(flow.acknowledge(sequence:1),"matching acknowledgment accepted")
  assertRuntime(!flow.expired(now:20),"acknowledged stream has no outstanding deadline")
  let globalMap:[String:Any] = ["from":["key_code":"a"],"to":[["key_code":"b"]]]
  let deviceMap:[String:Any] = ["from":["key_code":"caps_lock"],"to":[["key_code":"escape"]]]
  let profile:[String:Any] = ["simple_modifications":[globalMap],"devices":[["simple_modifications":[deviceMap]]]]
  assertRuntime(KarabinerAvailability.conflictingSources(profile:profile,sources:["a","caps_lock","c"]) == ["a","caps_lock"],"detect global and per-device simple modifications before complex rules")
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("karabiner runtime \(UUID())")
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:root) }
  let wrapper = root.appendingPathComponent("DNF.app")
  let wine = wrapper.appendingPathComponent("Contents/SharedSupport/wine/lib/wine/x86_64-unix/wine")
  try FileManager.default.createDirectory(at:wine.deletingLastPathComponent(),withIntermediateDirectories:true)
  try Data("#!/bin/sh\nexit 0\n".utf8).write(to:wine)
  try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:wine.path)
  let cli = root.appendingPathComponent("acknowledging-cli")
  try Data("#!/bin/sh\nwhile IFS= read -r line; do printf '%s\\n' \"$line\"; done\n".utf8).write(to:cli)
  try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:cli.path)
  let configuration = root.appendingPathComponent("karabiner.json")
  try Data("{\"profiles\":[{\"name\":\"test\",\"selected\":true,\"complex_modifications\":{\"rules\":[]}}]}".utf8).write(to:configuration)
  var p = KeyProfile(wrapperPath:wrapper.path); p.enabled = true; p.useKoreanPreset()
  let runtime = try KarabinerRuntime(profile:p,wrapper:wrapper,configuration:configuration,cli:cli,version:"16.3.0")
  assertRuntime(runtime.healthy,"real pipe acknowledgment connects without a GUI or host config mutation")
  var received: [KarabinerDeliveryMessage] = []
  try runtime.beginSession { received.append($0) }
  armRuntime(runtime)
  assertRuntime(runtime.healthy,"grant acknowledged without outstanding timeout")
  let first = try runtimeCommand(configuration)
  assertRuntime(sendRuntime(first.1,to:first.0) == first.1.count,"semantic datagram queued")
  let receiveDeadline = Date(timeIntervalSinceNow:0.1)
  while Date() < receiveDeadline { _ = RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.005)) }
  assertRuntime(received.count == 1 && received[0].target == .key(57),"current session delivers already-selected semantic Caps")
  runtime.invalidate()
  assertRuntime(sendRuntime(first.1,to:first.0) == -1,"focus loss immediately closes old input endpoint")
  try runtime.beginSession { received.append($0) }
  armRuntime(runtime)
  let second = try runtimeCommand(configuration)
  assertRuntime(second.0 != first.0,"each foreground entry has a different socket")
  _ = sendRuntime(first.1,to:second.0)
  let staleDeadline = Date(timeIntervalSinceNow:0.1)
  while Date() < staleDeadline { _ = RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.005)) }
  assertRuntime(received.count == 1,"old queued payload cannot affect a new focus session")
  _ = sendRuntime(second.1,to:second.0)
  let secondDeadline = Date(timeIntervalSinceNow:0.1)
  while Date() < secondDeadline { _ = RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.005)) }
  assertRuntime(received.count == 2,"new session accepts its own payload")
  runtime.renew(attested:true) // Leave an active renewal ACK in flight during focus loss.
  runtime.invalidate()
  try runtime.beginSession { received.append($0) }
  runtime.renew(attested:true)
  let afterPendingFocus = try runtimeCommand(configuration)
  _ = sendRuntime(afterPendingFocus.1,to:afterPendingFocus.0)
  let oldAckDeadline = Date(timeIntervalSinceNow:0.05)
  while Date() < oldAckDeadline { _ = RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.005)) }
  assertRuntime(received.count == 2,"previous generation ACK cannot authorize the new focus endpoint")
  assertRuntime(runtime.healthy,"discarding an invalidated generation ACK permits a fresh handshake")
  armRuntime(runtime)
  _ = sendRuntime(afterPendingFocus.1,to:afterPendingFocus.0)
  let freshAckDeadline = Date(timeIntervalSinceNow:0.05)
  while Date() < freshAckDeadline { _ = RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.005)) }
  assertRuntime(received.count == 3,"fresh focus delivers only after its own active ACK")
  runtime.invalidate(); runtime.close()
  let restored = try JSONSerialization.jsonObject(with:Data(contentsOf:configuration)) as! [String:Any]
  let selected = (restored["profiles"] as! [[String:Any]])[0]
  assertRuntime(((selected["complex_modifications"] as! [String:Any])["rules"] as! [Any]).isEmpty,"runtime close removes only owned rule")
  let stalled = try KarabinerRuntime(profile:p,wrapper:wrapper,configuration:configuration,cli:cli,version:"16.3.0")
  try stalled.beginSession { _ in assertRuntime(false,"expired session must reject delivery") }
  armRuntime(stalled)
  assertRuntime(stalled.healthy,"acknowledged active grant begins healthy")
  let interrupted = try runtimeCommand(configuration)
  Thread.sleep(forTimeInterval:0.65) // Deliberately stop this test's run loop beyond the core lease.
  assertRuntime(!stalled.healthy,"acknowledged grant expiry must be unhealthy even with no ACK outstanding")
  stalled.renew(attested:true)
  assertRuntime(!stalled.healthy,"renew cannot silently revive ownership after a grant gap")
  _ = sendRuntime(interrupted.1,to:interrupted.0)
  _ = RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
  stalled.close()
  assertRuntime(sendRuntime(interrupted.1,to:interrupted.0) == -1,"expired runtime cleanup closes its stale input endpoint")
  let delayedCLI = root.appendingPathComponent("delayed-renewal-cli")
  let delayedScript = """
  #!/bin/sh
  n=0
  while IFS= read -r line; do
    case "$line" in *'_active":1'*) n=$((n+1)); if [ "$n" -gt 1 ]; then sleep 0.25; fi ;; esac
    printf '%s\\n' "$line"
  done
  """
  try Data(delayedScript.utf8).write(to:delayedCLI)
  try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:delayedCLI.path)
  let delayed = try KarabinerRuntime(profile:p,wrapper:wrapper,configuration:configuration,cli:delayedCLI,version:"16.3.0")
  try delayed.beginSession { _ in assertRuntime(false,"late renewal must not revive delivery") }
  armRuntime(delayed)
  assertRuntime(delayed.healthy,"initial active grant is acknowledged before delayed-renewal scenario")
  Thread.sleep(forTimeInterval:0.25)
  delayed.renew(attested:true)
  assertRuntime(delayed.healthy,"renewal begins while previous confirmed grant is still live")
  Thread.sleep(forTimeInterval:0.2)
  assertRuntime(!delayed.healthy,"pending renewal must not extend the previous confirmed expiry before ACK")
  let lateDeadline = Date(timeIntervalSinceNow:0.15)
  while Date() < lateDeadline { _ = RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.005)) }
  assertRuntime(!delayed.healthy,"a late ACK cannot revive a session after confirmed grant continuity was lost")
  delayed.close()
  var conflicting = try JSONSerialization.jsonObject(with:Data(contentsOf:configuration)) as! [String:Any]
  var profiles = conflicting["profiles"] as! [[String:Any]]
  profiles[0]["simple_modifications"] = [["from":["key_code":"caps_lock"],"to":[["key_code":"escape"]]]]
  conflicting["profiles"] = profiles
  try JSONSerialization.data(withJSONObject:conflicting).write(to:configuration)
  p.bindings = [.init(source:0,target:.key(57))]
  do { _ = try KarabinerRuntime(profile:p,wrapper:wrapper,configuration:configuration,cli:cli,version:"16.3.0"); assertRuntime(false,"implicit adopted Caps simple conflict rejected") } catch {}
  print("PASS: Karabiner version, acknowledgment backpressure, conflict detection and fresh semantic session isolation")
 }
}
