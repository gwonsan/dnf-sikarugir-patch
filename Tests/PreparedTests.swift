import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: \(message)"); exit(1) }
}
func rejects(_ operation: () throws -> Void, _ message: String) {
    do { try operation(); print("FAIL: \(message)"); exit(1) } catch {}
}

@main struct PreparedTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DNF ready tests \(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("Prepared.app")
        let support = source.appendingPathComponent("Contents/SharedSupport")
        let assets = support.appendingPathComponent("dnf-ready")
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        let names = ["sourcehansans.ttc", "NeopleCustomURLStarter.exe", "NeopleInstallerStarter.exe"]
        let sha = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        for name in names { try Data("abc".utf8).write(to: assets.appendingPathComponent(name)) }
        try PropertyListSerialization.data(fromPropertyList: Dictionary(uniqueKeysWithValues: names.map { ($0, sha) }), format: .xml, options: 0).write(to: assets.appendingPathComponent("manifest.plist"))
        let settings: [String: Any] = ["DNFReadyVersion": "1", "D3DMETAL": 1, WrapperFactory.marker: "1", "CFBundleIdentifier": "test.prepared"]
        try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0).write(to: source.appendingPathComponent("Contents/Info.plist"))
        try Prepared.validate(source)
        let destination = root.appendingPathComponent("Apps With Spaces/DNF.app")
        try Prepared.copyBundle(source, to: destination)
        check(WrapperFactory.isOwned(destination), "copied ready apps can resume")
        check(!fm.fileExists(atPath: destination.appendingPathComponent("Contents/SharedSupport/prefix").path), "distributed apps contain no user prefix")
        rejects({ try Prepared.copyBundle(source, to: destination) }, "never overwrite an existing app")
        let link = root.appendingPathComponent("Dangling.app")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: root.appendingPathComponent("absent.app").path)
        rejects({ try Prepared.copyBundle(source, to: link) }, "never replace a dangling symlink")
        try Data("changed".utf8).write(to: assets.appendingPathComponent(names[0]))
        rejects({ try Prepared.copyBundle(source, to: root.appendingPathComponent("Tampered.app")) }, "reject modified font assets before creating a destination")
        check(!fm.fileExists(atPath: root.appendingPathComponent("Tampered.app").path), "tampered bundle leaves no partial app")
        try Data("abc".utf8).write(to: assets.appendingPathComponent(names[0]))
        try fm.createDirectory(at: support.appendingPathComponent("prefix"), withIntermediateDirectories: true)
        rejects({ try Prepared.validate(source) }, "never distribute a user's prefix")
        try fm.removeItem(at: support.appendingPathComponent("prefix"))
        let externalAssets = root.appendingPathComponent("external-assets")
        try fm.moveItem(at: assets, to: externalAssets)
        try fm.createSymbolicLink(atPath: assets.path, withDestinationPath: externalAssets.path)
        rejects({ try Prepared.validate(source) }, "never distribute an asset directory pointing outside the bundle")
        check(Prepared.fontDocument.contains("\"Source Han Sans K (TrueType)\"=\"sourcehansans.ttc\""), "register the Korean font face")
        check(Prepared.fontDocument.contains("[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Fonts]"), "register fonts in the legacy Windows section too")
        check(Prepared.fontDocument.contains("\"ＭＳ Ｐゴシック\"=\"Source Han Sans\""), "preserve fakejapanese aliases")
        check(!Prepared.fontDocument.contains("/Users/"), "font registration uses portable Windows paths")
        let prefix = destination.appendingPathComponent("Contents/SharedSupport/prefix/drive_c")
        let font = prefix.appendingPathComponent("windows/Fonts/sourcehansans.ttc")
        let plugin = prefix.appendingPathComponent("Program Files (x86)/NeoplePlugin")
        try fm.createDirectory(at: font.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: plugin, withIntermediateDirectories: true)
        try Data("font".utf8).write(to: font)
        try Bootstrap.fontCompletion.write(to: destination.appendingPathComponent("Contents/SharedSupport/dnf-fonts-ready"))
        try Data("prepared-v1\n".utf8).write(to: destination.appendingPathComponent("Contents/SharedSupport/dnf-ready-complete"))
        try Data("exe".utf8).write(to: plugin.appendingPathComponent("NeopleCustomURLStarter.exe"))
        check(!Prepared.isReady(destination), "missing InstallerStarter must retry despite success markers")
        try Data("exe".utf8).write(to: plugin.appendingPathComponent("NeopleInstallerStarter.exe"))
        check(Prepared.isReady(destination), "completed assets may resume without overwriting updated plugins")
        try Data().write(to: plugin.appendingPathComponent("NeopleCustomURLStarter.exe"))
        check(!Prepared.isReady(destination), "empty CustomURLStarter must retry despite success markers")
        try Data("exe".utf8).write(to: plugin.appendingPathComponent("NeopleCustomURLStarter.exe"))
        try Data().write(to: plugin.appendingPathComponent("NeopleInstallerStarter.exe"))
        check(!Prepared.isReady(destination), "empty InstallerStarter must retry despite success markers")
        print("PASS: prepared assets, checksum tampering, clean prefix, existing apps, symlinks, font registration")
    }
}
