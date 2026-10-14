import AppKit

enum Bootstrap {
    struct Resource {
        let name: String
        let url: String
        let sha256: String
    }
    static let template = Resource(name: "Template-1.0.21.tar.xz", url: "https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.21.tar.xz", sha256: "bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d")
    static let engine = Resource(name: "WS12WineSikarugir11.0_1.tar.xz", url: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir11.0_1.tar.xz", sha256: "67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e")
    static let winetricks = Resource(name: "winetricks", url: "https://raw.githubusercontent.com/Sikarugir-App/winetricks/0d05e972e08eadda2429f984a606eb8f9e5f63f5/src/winetricks", sha256: "322a3f788ae906bc8722a1c43145e91e95f30241b0b89438be3e664e0a579bdd")
    static let pluginPath = "Contents/SharedSupport/prefix/drive_c/Program Files (x86)/NeoplePlugin/NeopleCustomURLStarter.exe"
    static let fontPath = "Contents/SharedSupport/prefix/drive_c/windows/Fonts/sourcehansans.ttc"
    static let fontCompletion = Data("fakejapanese-v1\n".utf8)

    private static func fontAvailable(_ wrapper: URL) -> Bool {
        let attributes = try? Installer.fm.attributesOfItem(atPath: wrapper.appendingPathComponent(fontPath).path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0 > 0
    }

    static func fontsReady(_ wrapper: URL) -> Bool {
        let marker = wrapper.appendingPathComponent("Contents/SharedSupport/dnf-fonts-ready")
        return fontAvailable(wrapper) && (try? Data(contentsOf: marker)) == fontCompletion
    }

    static func download(_ resource: Resource) throws -> URL {
        let cache = Installer.support.appendingPathComponent("Downloads")
        try Installer.fm.createDirectory(at: cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = cache.appendingPathComponent(resource.name)
        if Installer.fm.fileExists(atPath: destination.path) {
            try WrapperFactory.verifyArchive(destination, sha256: resource.sha256)
            return destination
        }
        print("공식 서버에서 다운로드: \(resource.name)…")
        let partial = cache.appendingPathComponent(resource.name + "." + UUID().uuidString + ".part")
        defer { try? Installer.fm.removeItem(at: partial) }
        guard try Installer.run(URL(fileURLWithPath: "/usr/bin/curl"), ["--fail", "--location", "--proto", "=https", "--proto-redir", "=https", "--retry", "2", "--connect-timeout", "20", "--max-time", "900", "--output", partial.path, resource.url], timeout: 1000) == 0 else {
            throw PatchError(message: "공식 파일 다운로드에 실패했습니다: \(resource.name). 인터넷 연결을 확인하고 다시 실행하세요.")
        }
        try WrapperFactory.verifyArchive(partial, sha256: resource.sha256)
        try Installer.fm.moveItem(at: partial, to: destination)
        return destination
    }

    static func createWrapper(_ wrapper: URL) throws {
        if WrapperFactory.exists(wrapper) && !WrapperFactory.isOwned(wrapper) {
            throw PatchError(message: "기존 앱을 덮어쓰지 않습니다. 기존 DNF.app에는 설치.command를 실행하거나 새 경로를 지정하세요.")
        }
        #if arch(arm64)
        guard try Installer.run(URL(fileURLWithPath: "/usr/bin/arch"), ["-x86_64", "/usr/bin/true"]) == 0 else {
            throw PatchError(message: "Rosetta가 필요합니다. 터미널에서 softwareupdate --install-rosetta를 실행하고 약관에 동의한 뒤 다시 시도하세요.")
        }
        #endif
        if !WrapperFactory.exists(wrapper) {
            let templateFile = try download(template)
            let engineFile = try download(engine)
            print("빈 DNF.app 생성 중… D3DMetal을 활성화합니다.")
            try WrapperFactory.assemble(templateArchive: templateFile, engineArchive: engineFile, destination: wrapper)
        }
        try WrapperFactory.initializePrefix(wrapper)
        guard let smoke = makeWineProcess(arguments: ["C:\\windows\\system32\\cmd.exe", "/c", "exit 0"], wrapper: wrapper),
              try Installer.run(smoke.executableURL!, smoke.arguments!, environment: smoke.environment) == 0 else {
            throw PatchError(message: "새 앱의 Wine 실행 진단에 실패했습니다.")
        }
        if !fontsReady(wrapper) {
            let marker = wrapper.appendingPathComponent("Contents/SharedSupport/dnf-fonts-ready")
            if WrapperFactory.exists(marker) { try Installer.fm.removeItem(at: marker) }
            let tool = try download(winetricks)
            let installedTool = wrapper.appendingPathComponent("Contents/SharedSupport/winetricks")
            if Installer.fm.fileExists(atPath: installedTool.path) { try Installer.fm.removeItem(at: installedTool) }
            try Installer.fm.copyItem(at: tool, to: installedTool)
            try Installer.fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedTool.path)
            print("Configure와 같은 fakejapanese 폰트 설치 중…")
            var environment = smoke.environment!
            environment["PATH"] = installedTool.deletingLastPathComponent().path + ":" + wrapper.appendingPathComponent("Contents/Configure.app/Contents/Resources").path + ":" + environment["PATH"]!
            guard try Installer.run(URL(fileURLWithPath: "/bin/sh"), [installedTool.path, "-q", "--force", "fakejapanese"], environment: environment, timeout: 900) == 0,
                  fontAvailable(wrapper) else {
                throw PatchError(message: "폰트 설치에 실패했습니다. 새 앱의 Configure → Winetricks에서 fakejapanese를 실행한 뒤 처음설치.command를 다시 실행하세요.")
            }
            try fontCompletion.write(to: marker, options: .atomic)
        }
        print("새 앱 준비 완료: \(wrapper.path)")
    }

    static func setup(_ wrapper: URL, installer argument: String?) throws {
        if Installer.fm.fileExists(atPath: Installer.stateFile.path), try Installer.readState().wrapperPath != wrapper.path {
            throw PatchError(message: "다른 DNF.app에 적용한 패치가 있습니다. 해당 패치를 복원한 뒤 새 설치를 진행하세요.")
        }
        try createWrapper(wrapper)
        if !Installer.fm.fileExists(atPath: wrapper.appendingPathComponent(pluginPath).path) {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let file: URL
            if let argument { file = URL(fileURLWithPath: argument).standardizedFileURL }
            else {
                NSWorkspace.shared.open(URL(string: "https://df.nexon.com/data/client")!)
                print("공식 홈페이지에서 약관을 확인하고 플러그인을 받으세요. 내려받은 NeopleCustomURLBuilder.exe를 선택합니다.")
                let panel = NSOpenPanel()
                panel.title = "공식 NeopleCustomURLBuilder.exe 선택"
                panel.directoryURL = Installer.fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let selected = panel.url else {
                    throw PatchError(message: "설치 파일 선택을 취소했습니다. 새 DNF.app은 보존되며 다음 실행에서 이어서 진행합니다.")
                }
                file = selected
            }
            guard file.lastPathComponent.lowercased() == "neoplecustomurlbuilder.exe", Installer.fm.fileExists(atPath: file.path) else {
                throw PatchError(message: "NeopleCustomURLBuilder.exe 파일을 선택하세요.")
            }
            print("Wine의 네오플 설치 창에서 ‘설치’를 눌러 완료해 주세요. 이 버튼은 자동으로 누르지 않습니다…")
            guard let process = makeWineProcess(arguments: [file.path], wrapper: wrapper) else { throw PatchError(message: "Wine 엔진을 찾을 수 없습니다.") }
            try process.run()
            // The builder relaunches itself and its parent can exit before installation completes.
            let deadline = Date().addingTimeInterval(600)
            while !Installer.fm.fileExists(atPath: wrapper.appendingPathComponent(pluginPath).path) && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.5)
            }
            guard Installer.fm.fileExists(atPath: wrapper.appendingPathComponent(pluginPath).path) else {
                throw PatchError(message: "네오플 설치 완료를 확인하지 못했습니다. 설치 창을 확인한 뒤 처음설치.command를 다시 실행하세요. 새 앱은 보존됩니다.")
            }
        }
        try Installer.install(wrapper)
        NSWorkspace.shared.open(URL(string: "https://df.nexon.com")!)
        print("처음 설치 완료. 홈페이지에 로그인하고 GAME START를 눌러 게임을 내려받으세요.")
    }
}
