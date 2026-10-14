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
        let native = source.appendingPathComponent("Contents/MacOS/Sikarugir")
        try fm.createDirectory(at: native.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("downloaded native bundle must not be executed".utf8).write(to: native)
        let destination = root.appendingPathComponent("Apps With Spaces/DNF.app")
        let templateRoot = root.appendingPathComponent("fixture")
        let template = templateRoot.appendingPathComponent(WrapperFactory.templateName)
        try fm.createDirectory(at: template.appendingPathComponent("Contents/SharedSupport"), withIntermediateDirectories: true)
        try fm.createDirectory(at: template.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": "Template"], format: .xml, options: 0).write(to: template.appendingPathComponent("Contents/Info.plist"))
        let executable = template.appendingPathComponent("Contents/MacOS/Sikarugir")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let engine = templateRoot.appendingPathComponent("wswine.bundle/bin")
        try fm.createDirectory(at: engine, withIntermediateDirectories: true)
        try fm.copyItem(at: executable, to: engine.appendingPathComponent("wine"))
        let templateTar = root.appendingPathComponent("template.tar")
        let engineTar = root.appendingPathComponent("engine.tar")
        for (name, archive) in [(WrapperFactory.templateName, templateTar), ("wswine.bundle", engineTar)] {
            let status = try Installer.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-cf", archive.path, "-C", templateRoot.path, name])
            check(status == 0, "fixture archive")
        }
        try Prepared.copyBundle(source, to: destination, templateArchive: templateTar, engineArchive: engineTar)
        check((try? Data(contentsOf: destination.appendingPathComponent("Contents/MacOS/Sikarugir"))) != Data("downloaded native bundle must not be executed".utf8), "fresh installs assemble verified native code instead of copying the downloaded app")
        check(WrapperFactory.isOwned(destination), "copied ready apps can resume")
        check(!fm.fileExists(atPath: destination.appendingPathComponent("Contents/SharedSupport/prefix").path), "distributed apps contain no user prefix")
        rejects({ try Prepared.copyBundle(source, to: destination) }, "never overwrite an existing app")
        let originalData = destination.appendingPathComponent("user-data")
        try Data("preserve incomplete installation".utf8).write(to: originalData)
        try Prepared.rebuildIncomplete(source, wrapper: destination, templateArchive: templateTar, engineArchive: engineTar)
        let backups = try fm.contentsOfDirectory(at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("-before-v0.3.2-") }
        check(backups.count == 1, "keep one whole backup when rebuilding an incomplete app")
        let saved = try Data(contentsOf: backups[0].appendingPathComponent("user-data"))
        check(saved == Data("preserve incomplete installation".utf8), "rebuild preserves existing user files in the backup")
        check(!fm.fileExists(atPath: originalData.path), "new installation starts without the old incomplete environment")
        let waitingServer = destination.appendingPathComponent("Contents/SharedSupport/wine/bin/wineserver")
        try Data("#!/bin/sh\nexec /bin/sleep 10\n".utf8).write(to: waitingServer)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: waitingServer.path)
        rejects({ try Prepared.rebuildIncomplete(source, wrapper: destination, templateArchive: templateTar, engineArchive: engineTar) }, "active Wine prevents moving an incomplete app")
        let afterWait = try fm.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path).filter { $0.contains("-before-v0.3.2-") }
        check(afterWait.count == 1 && fm.fileExists(atPath: waitingServer.path), "active Wine leaves the original app in place")
        try fm.removeItem(at: waitingServer)
        rejects({ try Prepared.rebuildIncomplete(source, wrapper: destination, templateArchive: templateTar, engineArchive: templateTar) }, "failed rebuild keeps original app")
        check(WrapperFactory.isOwned(destination), "failed assembly does not move the original app")
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
        check(!Prepared.isReady(destination), "asset markers cannot hide an incomplete Windows environment")
        let windowsPrefix = destination.appendingPathComponent("Contents/SharedSupport/prefix")
        try fm.createDirectory(at: windowsPrefix.appendingPathComponent("drive_c/windows/system32"), withIntermediateDirectories: true)
        try fm.createDirectory(at: windowsPrefix.appendingPathComponent("drive_c/Program Files"), withIntermediateDirectories: true)
        for name in ["system.reg", "user.reg", "drive_c/windows/system32/cmd.exe"] {
            try Data("initialized".utf8).write(to: windowsPrefix.appendingPathComponent(name))
        }
        check(Prepared.isReady(destination), "completed assets may resume without overwriting updated plugins")
        rejects({ try Prepared.rebuildIncomplete(source, wrapper: destination, templateArchive: templateTar, engineArchive: engineTar) }, "never rebuild a complete Windows environment")
        try Data().write(to: plugin.appendingPathComponent("NeopleCustomURLStarter.exe"))
        check(!Prepared.isReady(destination), "empty CustomURLStarter must retry despite success markers")
        try Data("exe".utf8).write(to: plugin.appendingPathComponent("NeopleCustomURLStarter.exe"))
        try Data().write(to: plugin.appendingPathComponent("NeopleInstallerStarter.exe"))
        check(!Prepared.isReady(destination), "empty InstallerStarter must retry despite success markers")
        print("PASS: prepared assets, checksum tampering, clean prefix, existing apps, symlinks, font registration")
    }
}
