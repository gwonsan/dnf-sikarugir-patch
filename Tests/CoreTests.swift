import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: \(message)"); exit(1) }
}

@main struct CoreTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DNF tests \(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let wrapper = root.appendingPathComponent("Game With Spaces.app")
        let wine = wrapper.appendingPathComponent("Contents/SharedSupport/wine/bin/wine")
        let plugin = wrapper.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/Program Files (x86)/NeoplePlugin/NeopleCustomURLStarter.exe")
        try fm.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: plugin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: wine)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        try Data().write(to: plugin)
        let request = "Neople://test/?ticket=synthetic%2B123&literal=%22%26%25"
        guard let process = makeLaunchProcess(request: request, wrapper: wrapper) else {
            fatalError("valid launch rejected")
        }
        expect(process.arguments == ["C:\\Program Files (x86)\\NeoplePlugin\\NeopleCustomURLStarter.exe", request], "forward the original URL as one argument")
        expect(process.environment?["WINEPREFIX"] == wrapper.appendingPathComponent("Contents/SharedSupport/prefix").path, "use the selected prefix")
        expect(process.environment?["SikarugirAppWine11"] == "1", "enable Sikarugir Wine 11")
        expect(process.environment?["LC_ALL"] == "ko_KR.UTF-8", "start with Korean locale")
        for bad in ["https://example.com", "file:///tmp/a.exe", "neople://test\ncommand", "", "neople://test\u{0}"] {
            expect(makeLaunchProcess(request: bad, wrapper: wrapper) == nil, "reject non-Neople or control-character input")
        }
        try fm.removeItem(at: plugin)
        expect(makeLaunchProcess(request: request, wrapper: wrapper) == nil, "missing plugin must fail")
        print("PASS: isolated Wine prefix, intact URL, invalid inputs, Korean locale, missing plugin")
    }
}
