import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: \(message)"); exit(1) }
}

@main struct FontTests {
    static func main() {
        let exported = """
        Windows Registry Editor Version 5.00

        [HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]
        "Gulim"="Old Font"
        "MS Gothic"="Source Han Sans"
        "맑은 고딕"="Original Korean"

        [HKEY_CURRENT_USER\\Unrelated]
        "Gulim"="Ignore Me"
        "GulimChe"="Ignore Me Too"
        """
        let original = FontPatch.snapshot(exported)
        check(original["Gulim"] == "\"Gulim\"=\"Old Font\"", "snapshot only the intended registry section")
        check(original["맑은 고딕"] == "\"맑은 고딕\"=\"Original Korean\"", "preserve Korean keys")
        check(original["MS Gothic"] == nil && original["GulimChe"] == nil, "ignore unrelated aliases and sections")
        let applied = FontPatch.snapshot(FontPatch.installation())
        check(applied.count == 16 && applied["Gulim"] == "\"Gulim\"=\"Source Han Sans K\"", "emit the complete Korean fallback mapping")
        var current = applied
        current["Batang"] = "\"Batang\"=\"User Changed Font\""
        let restore = FontPatch.restoration(original: original, current: current)
        check(restore.contains("\"Gulim\"=\"Old Font\""), "restore an overwritten value")
        check(restore.contains("\"GulimChe\"=-"), "remove aliases introduced by the patch")
        check(!restore.contains("\"Batang\"="), "preserve changes made after installation")
        check(!restore.contains("MS Gothic"), "preserve fakejapanese mappings")
        let data = FontPatch.installation().data(using: .utf16)!
        check(String(data: data, encoding: .utf16)?.contains("맑은 고딕") == true, "registry data survives UTF-16 encoding")
        let mixed = exported.replacingOccurrences(of: "\"Gulim\"=\"Old Font\"", with: "\"gulim\"=\"Old Font\"")
        check(FontPatch.snapshot(mixed)["Gulim"] == "\"gulim\"=\"Old Font\"", "snapshot case-insensitive registry names without losing original spelling")
        let lowerCurrent = FontPatch.snapshot(FontPatch.installation().replacingOccurrences(of: "\"Gulim\"", with: "\"gulim\""))
        check(FontPatch.restoration(original: FontPatch.snapshot(mixed), current: lowerCurrent).contains("\"gulim\"=\"Old Font\""), "restore a case-preserving registry export")
        current.removeValue(forKey: "Dotum")
        let reinstall = FontPatch.installation(current: current)
        check(!reinstall.contains("\"Batang\"="), "reinstall preserves a later font edit")
        check(!reinstall.contains("\"Dotum\"="), "reinstall preserves a later deletion")
        check(reinstall.contains("\"Gulim\"=\"Source Han Sans K\""), "reinstall refreshes patch-owned aliases")
        print("PASS: selective snapshot, Korean aliases, restore/delete, later changes, Japanese mappings, UTF-16")
    }
}
