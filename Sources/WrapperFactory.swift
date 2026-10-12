import Foundation
import CryptoKit

enum WrapperFactory {
    static let templateName = "Template-1.0.21.app"
    static let marker = "DNFPatchBootstrapVersion"

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    static func isOwned(_ url: URL) -> Bool {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { return false }
        let settings = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        return settings?[marker] as? String == "1"
    }

    static func verifyArchive(_ url: URL, sha256: String) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hasher.update(data: data) }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == sha256 else { throw PatchError(message: "다운로드 파일의 SHA-256이 다릅니다. 해당 파일을 실행하지 않습니다: \(url.lastPathComponent)") }
    }

    static func assemble(templateArchive: URL, engineArchive: URL, destination: URL) throws {
        let fm = FileManager.default
        guard destination.pathExtension.lowercased() == "app", !exists(destination) else {
            throw PatchError(message: "새 앱 경로가 이미 존재하거나 .app 경로가 아닙니다. 기존 앱에는 설치.command를 사용하세요.")
        }
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".dnf-setup-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        guard try Installer.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xf", templateArchive.path, "-C", stage.path], timeout: 180) == 0 else {
            throw PatchError(message: "Sikarugir 템플릿 압축 해제에 실패했습니다.")
        }
        let app = stage.appendingPathComponent(templateName)
        let support = app.appendingPathComponent("Contents/SharedSupport")
        guard try Installer.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xf", engineArchive.path, "-C", support.path], timeout: 180) == 0 else {
            throw PatchError(message: "Wine 엔진 압축 해제에 실패했습니다.")
        }
        try fm.moveItem(at: support.appendingPathComponent("wswine.bundle"), to: support.appendingPathComponent("wine"))
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard var settings = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), options: [], format: nil) as? [String: Any],
              fm.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/Sikarugir").path),
              fm.isExecutableFile(atPath: support.appendingPathComponent("wine/bin/wine").path) else {
            throw PatchError(message: "템플릿 또는 엔진에 필요한 실행 파일이 없습니다.")
        }
        settings["CFBundleName"] = "DNF"
        settings["CFBundleIdentifier"] = "io.github.dnf-sikarugir-patch.wrapper." + UUID().uuidString.lowercased()
        settings[marker] = "1"
        settings["D3DMETAL"] = 1
        settings["D9VK"] = 1
        settings["CNC_DDRAW"] = 1
        settings["Skip Mono"] = 1
        settings["Skip Gecko"] = 1
        settings["Program Name and Path"] = "/Program Files (x86)/NeoplePlugin/NeopleCustomURLStarter.exe"
        settings["Program Flags"] = ""
        try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0).write(to: plistURL, options: .atomic)
        // moveItem fails if another process created the destination during extraction.
        try fm.moveItem(at: app, to: destination)
    }
}
