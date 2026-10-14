import Foundation
@main struct FreshReadyCheck {
    static func main() throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let wrapper = URL(fileURLWithPath: CommandLine.arguments[2])
        guard !WrapperFactory.exists(wrapper) else { fatalError("Test must start with no app or prefix") }
        try Prepared.prepare(source, wrapper: wrapper)
        guard WrapperFactory.prefixReady(wrapper), Prepared.isReady(wrapper) else { fatalError("Incomplete installation") }
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: wrapper.appendingPathComponent("Contents/drive_c").path)
        guard link == "SharedSupport/prefix/drive_c" else { fatalError("Nonportable link") }
        guard try Installer.wine(wrapper, ["C:\\windows\\system32\\cmd.exe", "/c", "exit 0"]) == 0 else { fatalError("Windows smoke failed") }
        try Installer.registry(wrapper, import: FontPatch.installation(current: nil))
        let fonts = try Installer.registry(wrapper)
        guard FontPatch.aliases.allSatisfy({ FontPatch.isOwned($0, fonts[$0]) }) else { fatalError("Korean fonts failed") }
        print("PASS: no existing app/prefix -> official local assembly -> Windows files -> both Neople starters -> Korean fonts -> cmd.exe")
    }
}
