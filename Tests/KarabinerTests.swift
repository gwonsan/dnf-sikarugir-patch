import Foundation
func check(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fputs("FAIL: \(message)\n",stderr); exit(1) } }
@main struct KarabinerTests {
 static func main() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("kara tests \(UUID())")
  try FileManager.default.createDirectory(at: root,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:root) }
  let wrapper = root.appendingPathComponent("Apps [1]/DNF.app")
  let legacy = Data("{\"version\":1,\"wrapperPath\":\"/Applications/DNF.app\",\"enabled\":true,\"bindings\":[]}".utf8)
  let migrated = try JSONDecoder().decode(KeyProfile.self,from:legacy)
  check(migrated.backend == .automatic,"old profiles migrate to automatic backend")
  check(KeyCatalog.keys.allSatisfy { KarabinerKeys.name($0.code) != nil },"every supported physical key has a Karabiner name")
  var p = KeyProfile(wrapperPath:wrapper.path); p.enabled = true
  p.bindings = [.init(source:57,target:.key(57)),.init(source:11,target:.key(57)),.init(source:0,target:.key(11)),.init(source:8,target:.key(0)),.init(source:2,target:.key(14)),.init(source:3,target:.disabled),.init(source:61,target:.toggleInputSource)]
  let rule = try KarabinerDeliveryRule.make(profile:p,wineExecutable:wrapper.appendingPathComponent("Contents/SharedSupport/wine/lib/wine/x86_64-unix/wine"),endpoint:"/tmp/test-only.sock",session:"test-only-session",generation:31)
  let json = try JSONSerialization.data(withJSONObject:rule,options:.sortedKeys)
  let text = String(decoding:json,as:UTF8.self)
  check(text.contains("frontmost_application_if") && text.contains("expression_if") && text.contains("system.now.milliseconds"),"every managed action gated by exact executable and expiring lease")
  let manipulators = rule["manipulators"] as! [[String:Any]]
  check(manipulators.allSatisfy { ($0["conditions"] as? [[String:Any]])?.count ?? 0 >= 2 },"including Caps carrier no unguarded manipulator")
  check((manipulators.first?["from"] as? [String:Any])?["key_code"] as? String == "escape","physical emergency shortcut precedes user modifier mappings")
  check(!text.contains("bundle_identifiers"),"bundle identifier OR must never broaden Wine scope")
  check(text.contains("send_user_command") && !text.contains("select_input_source"),"semantic transport avoids held global outputs and unreliable direct language selection")
  let config = root.appendingPathComponent("karabiner.json")
  let userRule: [String:Any] = ["description":"user rule","manipulators":[],"unknown":17]
  let original: [String:Any] = ["global":["unknown":"keep"],"profiles":[["name":"A","selected":true,"simple_modifications":[],"complex_modifications":["parameters":["user":7],"rules":[userRule]]],["name":"B","selected":false,"complex_modifications":["rules":[userRule]]]]]
  try JSONSerialization.data(withJSONObject:original).write(to:config)
  let store = KarabinerConfigStore(file:config)
  let revision = try store.revision()
  try store.install(rule:rule,identity:KarabinerRule.identity(wrapper:wrapper),expectedRevision:revision)
  let installed = try JSONSerialization.jsonObject(with:Data(contentsOf:config)) as! [String:Any]
  let profiles = installed["profiles"] as! [[String:Any]]
  let complex = profiles[0]["complex_modifications"] as! [String:Any]
  let rules = complex["rules"] as! [[String:Any]]
  check(rules.count == 2 && rules[1]["unknown"] as? Int == 17,"prepend only owned scoped rule and preserve existing rules")
  check((complex["parameters"] as? [String:Int])?["user"] == 7,"preserve complex parameters")
  check((installed["global"] as? [String:String])?["unknown"] == "keep","preserve unknown global fields")
  do { try store.install(rule:rule,identity:KarabinerRule.identity(wrapper:wrapper),expectedRevision:revision); check(false,"stale revision rejected") } catch {}
  let after = try store.revision()
  try store.install(rule:rule,identity:KarabinerRule.identity(wrapper:wrapper),expectedRevision:after)
  try store.remove(identity:KarabinerRule.identity(wrapper:wrapper))
  let restored = try JSONSerialization.jsonObject(with:Data(contentsOf:config)) as! NSDictionary
  check(restored == original as NSDictionary,"removing owned rule semantically restores all user data")
  check(FileManager.default.fileExists(atPath:store.backup.path),"initial bytes backed up before mutation")
  var lease = KarabinerLease()
  let generation = lease.invalidate()
  check(lease.issue(generation:generation,now:1000,attested:true)?.expires == 1500,"lease lasts only 500ms")
  _ = lease.invalidate()
  check(lease.issue(generation:generation,now:1001,attested:true) == nil,"stale attestation cannot reactivate after focus loss")
  check(lease.issue(generation:lease.generation,now:1001,attested:false) == nil,"unattested foreground never gets lease")
  let cli = URL(fileURLWithPath:"/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli")
  if FileManager.default.isExecutableFile(atPath:cli.path) {
    let fixture = root.appendingPathComponent("lint.json")
    try JSONSerialization.data(withJSONObject:["title":"DNF TUI tests","rules":[rule]]).write(to:fixture)
    let process = Process(); process.executableURL = cli; process.arguments = ["--lint-complex-modifications",fixture.path]
    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    check(process.terminationStatus == 0,"installed Karabiner parses generated regex/expression/actions")
  }
  if CommandLine.arguments.count == 2 {
    try JSONSerialization.data(withJSONObject:["title":"DNF TUI tests","rules":[rule]],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
  }
  print("PASS: backend migration, semantic scoped rules, config preservation, revisions and stale lease invalidation")
 }
}
