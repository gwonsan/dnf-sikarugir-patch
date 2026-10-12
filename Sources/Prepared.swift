import AppKit

enum Prepared {
    static let assetNames = Set(["sourcehansans.ttc", "NeopleCustomURLStarter.exe", "NeopleInstallerStarter.exe"])
    static let assetPath = "Contents/SharedSupport/dnf-ready"

    static func validate(_ source: URL) throws {
        let settings = NSDictionary(contentsOf: source.appendingPathComponent("Contents/Info.plist"))
        guard (try? Installer.fm.destinationOfSymbolicLink(atPath: source.path)) == nil,
              settings?["DNFReadyVersion"] as? String == "1",
              (settings?["D3DMETAL"] as? NSNumber)?.intValue == 1,
              !WrapperFactory.exists(source.appendingPathComponent("Contents/SharedSupport/prefix")),
              !WrapperFactory.exists(source.appendingPathComponent("Contents/SharedSupport/Logs")) else {
            throw PatchError(message: "준비된 배포용 DNF.app이 아닙니다. 사용자 prefix나 로그를 포함한 앱은 사용할 수 없습니다.")
        }
        let directory = source.appendingPathComponent(assetPath)
        let manifestURL = directory.appendingPathComponent("manifest.plist")
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              try manifestURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw PatchError(message: "준비된 파일과 목록은 앱 내부에 있어야 합니다.")
        }
        guard let manifest = try PropertyListSerialization.propertyList(from: Data(contentsOf: manifestURL), options: [], format: nil) as? [String: String],
              Set(manifest.keys) == assetNames,
              Set(try Installer.fm.contentsOfDirectory(atPath: directory.path)) == assetNames.union(["manifest.plist"]) else {
            throw PatchError(message: "준비된 앱의 파일 목록이 올바르지 않습니다.")
        }
        for name in assetNames {
            let file = directory.appendingPathComponent(name)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw PatchError(message: "배포 파일은 일반 파일이어야 합니다: \(name)") }
            try WrapperFactory.verifyArchive(file, sha256: manifest[name]!)
        }
    }

    static func copyBundle(_ source: URL, to destination: URL) throws {
        try validate(source)
        guard destination.pathExtension.lowercased() == "app", !WrapperFactory.exists(destination) else {
            throw PatchError(message: "기존 앱을 덮어쓰지 않습니다. 다른 새 앱 경로를 지정하세요.")
        }
        let parent = destination.deletingLastPathComponent()
        try Installer.fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staged = parent.appendingPathComponent(".dnf-ready-\(UUID().uuidString).app")
        defer { try? Installer.fm.removeItem(at: staged) }
        try Installer.fm.copyItem(at: source, to: staged)
        let plist = staged.appendingPathComponent("Contents/Info.plist")
        var settings = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), options: [], format: nil) as! [String: Any]
        settings["CFBundleIdentifier"] = "io.github.dnf-sikarugir-patch.wrapper." + UUID().uuidString.lowercased()
        settings[WrapperFactory.marker] = "1"
        try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0).write(to: plist, options: .atomic)
        try Installer.fm.moveItem(at: staged, to: destination)
    }

    static var fontDocument: String {
        let weights = [" ExtraLight", " Light", " Normal", "", " Medium", " Bold", " Heavy"]
        let faces = ["Source Han Sans SC", "Source Han Sans TC", "Source Han Sans", "Source Han Sans K"]
        let japanese = ["Meiryo", "Meiryo UI", "MS Gothic", "MS PGothic", "MS Mincho", "MS PMincho", "MS UI Gothic", "UD Digi KyoKasho N-R", "UD Digi KyoKasho NK-R", "UD Digi KyoKasho NP-R", "Yu Gothic", "Yu Gothic UI", "Yu Mincho", "メイリオ", "ＭＳ ゴシック", "ＭＳ Ｐゴシック", "ＭＳ 明朝", "ＭＳ Ｐ明朝"]
        let registered = faces.flatMap { face in weights.map { "\"\(face)\($0) (TrueType)\"=\"sourcehansans.ttc\"" } }
        let aliases = japanese.map { "\"\($0)\"=\"Source Han Sans\"" }
        let sections = ["Windows NT", "Windows"].map {
            "[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\\($0)\\CurrentVersion\\Fonts]\r\n" + registered.joined(separator: "\r\n")
        }
        return "Windows Registry Editor Version 5.00\r\n\r\n" + sections.joined(separator: "\r\n\r\n") + "\r\n\r\n" + FontPatch.section + "\r\n" + aliases.joined(separator: "\r\n") + "\r\n"
    }

    static func isReady(_ wrapper: URL) -> Bool {
        guard (try? Data(contentsOf: wrapper.appendingPathComponent("Contents/SharedSupport/dnf-ready-complete"))) == Data("prepared-v1\n".utf8),
              Bootstrap.fontsReady(wrapper) else { return false }
        // Neople may update installed executables, so don't compare them to the bundled version's hash.
        return [Bootstrap.pluginPath, Bootstrap.pluginPath.replacingOccurrences(of: "NeopleCustomURLStarter.exe", with: "NeopleInstallerStarter.exe")].allSatisfy {
            guard let values = try? wrapper.appendingPathComponent($0).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true && (values.fileSize ?? 0) > 0
        }
    }

    static func prepare(_ source: URL, wrapper: URL) throws {
        try validate(source)
        guard source.standardizedFileURL != wrapper.standardizedFileURL else { throw PatchError(message: "배포 앱과 다른 설치 경로를 지정하세요.") }
        if WrapperFactory.exists(wrapper) {
            guard WrapperFactory.isOwned(wrapper), NSDictionary(contentsOf: wrapper.appendingPathComponent("Contents/Info.plist"))?["DNFReadyVersion"] as? String == "1" else {
                throw PatchError(message: "기존 앱을 덮어쓰지 않습니다. 기존 앱에는 설치.command를 사용하세요.")
            }
        } else { try copyBundle(source, to: wrapper) }
        let support = wrapper.appendingPathComponent("Contents/SharedSupport")
        let wine = support.appendingPathComponent("wine")
        if !Installer.fm.isExecutableFile(atPath: wine.appendingPathComponent("bin/wine").path) {
            guard !WrapperFactory.exists(wine) else { throw PatchError(message: "앱의 Wine 엔진이 손상됐습니다. 새 설치 경로를 지정하세요.") }
            let archive = try Bootstrap.download(Bootstrap.engine)
            let stage = support.appendingPathComponent(".dnf-engine-\(UUID().uuidString)")
            try Installer.fm.createDirectory(at: stage, withIntermediateDirectories: false)
            defer { try? Installer.fm.removeItem(at: stage) }
            guard try Installer.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xf", archive.path, "-C", stage.path], timeout: 180) == 0,
                  Installer.fm.isExecutableFile(atPath: stage.appendingPathComponent("wswine.bundle/bin/wine").path) else { throw PatchError(message: "Wine 엔진 압축 해제에 실패했습니다.") }
            try Installer.fm.moveItem(at: stage.appendingPathComponent("wswine.bundle"), to: wine)
        }
        if !Installer.fm.fileExists(atPath: support.appendingPathComponent("prefix/system.reg").path) {
            print("이 Mac에 맞는 Wine prefix 초기화 중…")
            guard try Installer.run(wrapper.appendingPathComponent("Contents/MacOS/Sikarugir"), ["WSS-wineprefixcreate"], timeout: 300) == 0 else { throw PatchError(message: "Wine 초기화에 실패했습니다. 시작.command를 다시 실행하세요.") }
        }
        let ready = support.appendingPathComponent("dnf-ready-complete")
        if !isReady(wrapper) {
            print("동봉한 폰트와 네오플 플러그인 설정 중…")
            let destinations = ["sourcehansans.ttc": Bootstrap.fontPath, "NeopleCustomURLStarter.exe": Bootstrap.pluginPath, "NeopleInstallerStarter.exe": Bootstrap.pluginPath.replacingOccurrences(of: "NeopleCustomURLStarter.exe", with: "NeopleInstallerStarter.exe")]
            for (name, path) in destinations {
                let target = wrapper.appendingPathComponent(path)
                try Installer.fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if WrapperFactory.exists(target) { try Installer.fm.removeItem(at: target) }
                try Installer.fm.copyItem(at: source.appendingPathComponent(assetPath).appendingPathComponent(name), to: target)
            }
            try Installer.registry(wrapper, import: fontDocument)
            try Bootstrap.fontCompletion.write(to: support.appendingPathComponent("dnf-fonts-ready"), options: .atomic)
            try Data("prepared-v1\n".utf8).write(to: ready, options: .atomic)
        }
        guard try Installer.wine(wrapper, ["C:\\windows\\system32\\cmd.exe", "/c", "exit 0"]) == 0 else { throw PatchError(message: "Wine 실행 진단에 실패했습니다.") }
        print("준비된 앱 설치 완료: \(wrapper.path)")
    }

    static func install(_ source: URL, wrapper: URL) throws {
        let existing = Installer.fm.fileExists(atPath: Installer.stateFile.path) ? try Installer.readState() : nil
        if let existing, existing.wrapperPath != wrapper.path { throw PatchError(message: "다른 앱에 적용한 패치가 있습니다. 먼저 복원.command를 실행하세요.") }
        let preparedWrapper = NSDictionary(contentsOf: wrapper.appendingPathComponent("Contents/Info.plist"))?["DNFReadyVersion"] as? String == "1"
        if !(existing?.wrapperPath == wrapper.path && makeLaunchProcess(request: "neople://patch-check", wrapper: wrapper) != nil && (!preparedWrapper || isReady(wrapper))) {
            try prepare(source, wrapper: wrapper)
        }
        try Installer.install(wrapper)
        NSWorkspace.shared.open(URL(string: "https://df.nexon.com")!)
        print("홈페이지 실행 연결 완료. 로그인하고 GAME START를 눌러 주세요.")
    }
}
