import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: \(message)"); exit(1) }
}

func rejects(_ operation: () throws -> Void, _ message: String) {
    do { try operation(); print("FAIL: \(message)"); exit(1) } catch {}
}

func tar(_ source: URL, _ name: String, _ archive: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    p.arguments = ["-cf", archive.path, "-C", source.path, name]
    try p.run(); p.waitUntilExit()
    check(p.terminationStatus == 0, "fixture archive creation")
}

@main struct BootstrapTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DNF setup tests \(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let integrity = root.appendingPathComponent("checksum")
        try Data("abc".utf8).write(to: integrity)
        try WrapperFactory.verifyArchive(integrity, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try Data("changed".utf8).write(to: integrity)
        rejects({ try WrapperFactory.verifyArchive(integrity, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") }, "changed downloads must be rejected")

        let template = root.appendingPathComponent("Template-1.0.21.app")
        let contents = template.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: contents.appendingPathComponent("SharedSupport"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleName": "Template", "CFBundleIdentifier": "fixture.template", "CFBundleVersion": "1.0.21", "D3DMETAL": 0, "D9VK": 1, "CustomTemplateSetting": "keep"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let launcher = contents.appendingPathComponent("MacOS/Sikarugir")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: launcher)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        let engine = root.appendingPathComponent("wswine.bundle/bin")
        try fm.createDirectory(at: engine, withIntermediateDirectories: true)
        let wine = engine.appendingPathComponent("wine")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: wine)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        let templateTar = root.appendingPathComponent("template.tar")
        let engineTar = root.appendingPathComponent("engine.tar")
        try tar(root, "Template-1.0.21.app", templateTar)
        try tar(root, "wswine.bundle", engineTar)
        let app = root.appendingPathComponent("Apps With Spaces/DNF.app")
        try WrapperFactory.assemble(templateArchive: templateTar, engineArchive: engineTar, destination: app)
        let settings = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), options: [], format: nil) as! [String: Any]
        check(settings["D3DMETAL"] as? Int == 1, "enable the user-required D3DMetal renderer")
        check(settings["Program Name and Path"] as? String == "/Program Files (x86)/NeoplePlugin/NeopleCustomURLStarter.exe", "set the installed plugin as the executable")
        check(settings["CustomTemplateSetting"] as? String == "keep", "preserve unrelated template settings")
        check(fm.isExecutableFile(atPath: app.appendingPathComponent("Contents/SharedSupport/wine/bin/wine").path), "engine is inside the new app")
        check(WrapperFactory.isOwned(app), "new wrapper can resume")
        // A zero exit or an early system.reg must not count as a usable Windows environment.
        let prefix = app.appendingPathComponent("Contents/SharedSupport/prefix")
        try fm.createDirectory(at: prefix, withIntermediateDirectories: true)
        try Data("partial registry".utf8).write(to: prefix.appendingPathComponent("system.reg"))
        check(!WrapperFactory.prefixReady(app), "partial Windows environment is not complete")
        rejects({ try WrapperFactory.initializePrefix(app) }, "zero launcher exit without Windows files is rejected")
        let installedLauncher = app.appendingPathComponent("Contents/MacOS/Sikarugir")
        let script = """
        #!/bin/sh
        set -eu
        [ "$1" = WSS-wineprefixcreate ]
        base="$(dirname "$0")/../SharedSupport/prefix"
        mkdir -p "$base/drive_c/windows/system32" "$base/drive_c/Program Files" "$base/drive_c/Program Files (x86)"
        for f in system.reg user.reg drive_c/windows/system32/cmd.exe; do
          echo initialized > "$base/$f"
        done
        echo 'initialization diagnostic'
        """
        try Data(script.utf8).write(to: installedLauncher)
        try WrapperFactory.initializePrefix(app)
        check(WrapperFactory.prefixReady(app), "fresh initialization creates complete Windows files")
        let log = app.appendingPathComponent("Contents/SharedSupport/Logs/DNF-prefix-init.log")
        let diagnostic = try String(contentsOf: log, encoding: .utf8)
        check(diagnostic.contains("initialization diagnostic"), "initialization output is available for troubleshooting")
        try Data("#!/bin/sh\nexit 42\n".utf8).write(to: installedLauncher)
        try WrapperFactory.initializePrefix(app)
        check(WrapperFactory.prefixReady(app), "complete prefix is preserved without rerunning launcher")
        try fm.removeItem(at: prefix.appendingPathComponent("user.reg"))
        rejects({ try WrapperFactory.initializePrefix(app) }, "nonzero initialization does not proceed to plugin setup")
        try Data("#!/bin/sh\nexec /bin/sleep 10\n".utf8).write(to: installedLauncher)
        let started = Date()
        rejects({ try WrapperFactory.initializePrefix(app, timeout: 0.2) }, "hung initialization terminates with diagnostic")
        check(Date().timeIntervalSince(started) < 3, "initialization timeout is bounded")
        let font = app.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/windows/Fonts/sourcehansans.ttc")
        let ready = app.appendingPathComponent("Contents/SharedSupport/dnf-fonts-ready")
        try fm.createDirectory(at: font.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("copied before registration".utf8).write(to: font)
        check(!Bootstrap.fontsReady(app), "an interrupted font copy must not skip registration on resume")
        try Data("fakejapanese-v1\n".utf8).write(to: ready)
        check(Bootstrap.fontsReady(app), "completed fonts do not rerun on resume")
        try Data().write(to: font)
        check(!Bootstrap.fontsReady(app), "empty fonts invalidate a stale success marker")
        try fm.removeItem(at: font)
        check(!Bootstrap.fontsReady(app), "missing fonts invalidate a stale success marker")
        let sentinel = app.appendingPathComponent("game-data")
        try Data("keep".utf8).write(to: sentinel)
        rejects({ try WrapperFactory.assemble(templateArchive: templateTar, engineArchive: engineTar, destination: app) }, "never overwrite an existing app")
        let preserved = try Data(contentsOf: sentinel)
        check(preserved == Data("keep".utf8), "preserve existing game data")
        let link = root.appendingPathComponent("Dangling.app")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: root.appendingPathComponent("absent.app").path)
        rejects({ try WrapperFactory.assemble(templateArchive: templateTar, engineArchive: engineTar, destination: link) }, "never replace a dangling symlink")
        rejects({ try WrapperFactory.assemble(templateArchive: templateTar, engineArchive: templateTar, destination: root.appendingPathComponent("Broken.app")) }, "reject missing engine")
        check(!fm.fileExists(atPath: root.appendingPathComponent("Broken.app").path), "failed assembly leaves no partial destination")
        let leftovers = try fm.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".dnf-setup-") }
        check(leftovers.isEmpty, "failed assembly cleans temporary extraction")
        print("PASS: integrity, fresh wrapper, D3DMetal, executable path, ownership, existing apps, symlinks and failure cleanup")
    }
}
