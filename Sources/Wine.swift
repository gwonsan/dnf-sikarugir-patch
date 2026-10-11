import Foundation

func makeLaunchProcess(request: String, wrapper: URL) -> Process? {
    guard request.lowercased().hasPrefix("neople://"),
          !request.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
    let contents = wrapper.appendingPathComponent("Contents")
    let wine = contents.appendingPathComponent("SharedSupport/wine/bin/wine")
    let prefix = contents.appendingPathComponent("SharedSupport/prefix")
    let plugin = prefix.appendingPathComponent("drive_c/Program Files (x86)/NeoplePlugin/NeopleCustomURLStarter.exe")
    guard FileManager.default.isExecutableFile(atPath: wine.path),
          FileManager.default.fileExists(atPath: plugin.path) else { return nil }
    let process = Process()
    process.executableURL = wine
    process.arguments = ["C:\\Program Files (x86)\\NeoplePlugin\\NeopleCustomURLStarter.exe", request]
    process.currentDirectoryURL = plugin.deletingLastPathComponent()
    var env = ProcessInfo.processInfo.environment
    env["WINEPREFIX"] = prefix.path
    env["WINESERVER"] = contents.appendingPathComponent("SharedSupport/wine/bin/wineserver").path
    env["WINELOADER"] = wine.path
    env["PATH"] = wine.deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin"
    let frameworks = contents.appendingPathComponent("Frameworks")
    let wineRoot = contents.appendingPathComponent("SharedSupport/wine")
    env["DYLD_FALLBACK_LIBRARY_PATH"] = [wineRoot.appendingPathComponent("lib").path, wineRoot.appendingPathComponent("lib64").path, frameworks.path, frameworks.appendingPathComponent("GStreamer.framework/Libraries").path, "/usr/lib", "/usr/libexec", "/usr/lib/system"].joined(separator: ":")
    env["CX_ROOT"] = wineRoot.path
    env["GST_PLUGIN_PATH"] = frameworks.appendingPathComponent("GStreamer.framework/Libraries/gstreamer-1.0").path
    env["ROSETTA_ADVERTISE_AVX"] = "1"
    env["FEX_X87REDUCEDPRECISION"] = "1"
    env["CX_FWD_COMPAT_GL_CTX"] = "1"
    env["WINEBOOT_HIDE_DIALOG"] = "1"
    for (key, directory) in [("D3DMETAL", "d3dmetal"), ("D9VK", "d9vk"), ("CNCD", "cnc_ddraw"), ("DXMT", "dxmt")] {
        env["WINEDLLPATH_\(key)"] = frameworks.appendingPathComponent("renderer/\(directory)/wine").path
    }
    env["CX_D3DMETALPATH"] = frameworks.appendingPathComponent("renderer/d3dmetal").path
    for key in ["CX_APPLEGPT_LIBD3DSHARED_PATH", "CX_APPLEGPTK_LIBD3DSHARED_PATH"] {
        env[key] = frameworks.appendingPathComponent("renderer/d3dmetal/external/libd3dshared.dylib").path
    }
    env["WINEDEBUG"] = "-all"
    env["SikarugirAppWine11"] = "1"
    env["LANG"] = "ko_KR.UTF-8"
    env["LC_ALL"] = "ko_KR.UTF-8"
    env["LC_CTYPE"] = "ko_KR.UTF-8"
    let settings = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")) as? [String: Any] ?? [:]
    env["WINEESYNC"] = String((settings["WINEESYNC"] as? NSNumber)?.intValue ?? 1)
    env["WINEMSYNC"] = String((settings["WINEMSYNC"] as? NSNumber)?.intValue ?? 1)
    var rendererPaths: [String] = []
    var overrides: [String] = []
    for (key, directory, libraries) in [("D3DMETAL", "d3dmetal", "dxgi,d3d11,d3d12"), ("D9VK", "d9vk", "d3d8,d3d9"), ("CNC_DDRAW", "cnc_ddraw", "ddraw")] {
        if (settings[key] as? NSNumber)?.boolValue == true {
            rendererPaths.append(contents.appendingPathComponent("Frameworks/renderer/\(directory)/wine").path)
            overrides.append("\(libraries)=n,b")
        }
    }
    env["WINEDLLPATH"] = (rendererPaths + [contents.appendingPathComponent("SharedSupport/wine/lib/wine").path]).joined(separator: ":")
    env["WINEDLLPATH_PREPEND"] = rendererPaths.joined(separator: ":")
    env["WINEDLLOVERRIDES"] = overrides.joined(separator: ";")
    process.environment = env
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    return process
}
