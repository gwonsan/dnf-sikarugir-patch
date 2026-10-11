import Foundation
import Darwin

enum PatchLock {
    static func withLock<T>(directory: URL, _ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(directory.appendingPathComponent("operation.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw NSError(domain: "DNFPatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "설치 잠금 파일을 열지 못했습니다."])
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw NSError(domain: "DNFPatch", code: 2, userInfo: [NSLocalizedDescriptionKey: "다른 설치 또는 복원 작업이 실행 중입니다. 끝난 뒤 다시 실행해 주세요."])
        }
        defer { flock(descriptor, LOCK_UN) }
        // Keep the lock inode: deleting it could allow a second concurrent lock.
        return try operation()
    }
}
