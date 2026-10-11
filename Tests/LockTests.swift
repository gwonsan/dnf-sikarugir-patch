import Foundation

@main struct LockTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DNF-lock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var entered = false
        try PatchLock.withLock(directory: directory) {
            do {
                try PatchLock.withLock(directory: directory) { entered = true }
            } catch { }
        }
        guard !entered else { print("FAIL: concurrent installation entered the transaction"); exit(1) }
        let value = try PatchLock.withLock(directory: directory) { 42 }
        guard value == 42 else { fatalError("lock did not release") }
        do {
            try PatchLock.withLock(directory: directory) { throw NSError(domain: "test", code: 1) }
        } catch { }
        let retry = try PatchLock.withLock(directory: directory) { true }
        guard retry else { fatalError("lock did not release after error") }
        print("PASS: exclusive transaction, release on success and failure")
    }
}
