import Foundation

func expect(_ value: Bool, _ message: String) {
    if !value { fputs("FAIL: \(message)\n",stderr); exit(1) }
}
@main struct BundleMetadataTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DNF bundle metadata \(UUID())")
        defer { try? fm.removeItem(at:root) }
        let app = root.appendingPathComponent("Helper.app")
        let child = app.appendingPathComponent("Contents/Resources/Keyboard.app")
        for (bundle, identifier) in [(child,"test.dnf.keyboard"),(app,"test.dnf.parent")] {
            try fm.createDirectory(at:bundle.appendingPathComponent("Contents/MacOS"),withIntermediateDirectories:true)
            try fm.copyItem(at:URL(fileURLWithPath:"/usr/bin/true"),to:bundle.appendingPathComponent("Contents/MacOS/helper"))
            let info:[String:Any] = ["CFBundleIdentifier":identifier,"CFBundleExecutable":"helper","CFBundleName":"Fixture","CFBundlePackageType":"APPL"]
            try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:bundle.appendingPathComponent("Contents/Info.plist"))
            expect(try Installer.run(URL(fileURLWithPath:"/usr/bin/codesign"),["--force","--sign","-",bundle.path]) == 0,"fixture signs")
        }
        let infoFile = app.appendingPathComponent("Contents/Info.plist")
        let before = try Data(contentsOf:infoFile)
        for bundle in [app,child] {
            expect(try Installer.run(URL(fileURLWithPath:"/usr/bin/xattr"),["-wx","com.apple.FinderInfo",String(repeating:"00",count:8)+"0400"+String(repeating:"00",count:22),bundle.path]) == 0,"attach Finder metadata to signed copy")
        }
        expect(try Installer.run(URL(fileURLWithPath:"/usr/bin/codesign"),["--verify","--deep","--strict",app.path]) != 0,"Finder metadata reproduces signature failure")
        try Installer.verifyHelperBundle(app)
        expect(try Data(contentsOf:infoFile) == before,"normalization never edits signed content")
        var changed = try PropertyListSerialization.propertyList(from:before,options:[],format:nil) as! [String:Any]
        changed["CFBundleName"] = "Tampered"
        try PropertyListSerialization.data(fromPropertyList:changed,format:.xml,options:0).write(to:infoFile)
        do { try Installer.verifyHelperBundle(app); expect(false,"real signed-content tampering remains rejected") } catch {}
        print("PASS: copied Finder metadata cleaned, nested signature valid, signed-content tampering rejected")
    }
}
