import Foundation

enum FontPatch {
    static let aliases = ["Batang", "BatangChe", "Dotum", "DotumChe", "Gulim", "GulimChe", "Gungsuh", "GungsuhChe", "Malgun Gothic", "바탕", "바탕체", "돋움", "돋움체", "굴림", "굴림체", "맑은 고딕"]
    static let section = "[HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]"

    static func snapshot(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var inSection = false
        var continuation: String?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inSection = line.caseInsensitiveCompare(section) == .orderedSame
                continuation = nil
                continue
            }
            guard inSection else { continue }
            if let alias = continuation {
                result[alias, default: ""] += "\r\n  " + line
                if !line.hasSuffix("\\") { continuation = nil }
            } else if let alias = aliases.first(where: { line.lowercased().hasPrefix("\"\($0.lowercased())\"=") }) {
                result[alias] = line
                if line.hasSuffix("\\") { continuation = alias }
            }
        }
        return result
    }

    private static func document(_ lines: [String]) -> String {
        "Windows Registry Editor Version 5.00\r\n\r\n" + section + "\r\n" + lines.joined(separator: "\r\n") + "\r\n"
    }

    static func installation(current: [String: String]? = nil) -> String {
        document(aliases.filter { alias in
            current == nil || isOwned(alias, current?[alias])
        }.map { "\"\($0)\"=\"Source Han Sans K\"" })
    }

    static func isOwned(_ alias: String, _ line: String?) -> Bool {
        line?.caseInsensitiveCompare("\"\(alias)\"=\"Source Han Sans K\"") == .orderedSame
    }

    static func restoration(original: [String: String], current: [String: String]) -> String {
        document(aliases.compactMap { alias in
            guard isOwned(alias, current[alias]) else { return nil }
            return original[alias] ?? "\"\(alias)\"=-"
        })
    }
}
