import Foundation
import Darwin

enum PatchLock {
    enum Failure: LocalizedError {
        case unavailable, busy
        var errorDescription: String? {
            switch self {
            case .unavailable: return "작업 잠금 파일을 열지 못했습니다. 설치 자료 폴더의 권한을 확인하세요."
            case .busy: return "설치·복원 또는 게임 실행 요청을 처리 중입니다. 끝난 뒤 다시 시도해 주세요."
            }
        }
    }

    final class Lease {
        private var descriptor: Int32
        fileprivate init(_ descriptor: Int32) { self.descriptor = descriptor }
        func release() {
            guard descriptor >= 0 else { return }
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }
        deinit { release() }
    }

    static func acquire(directory: URL, shared: Bool = false) throws -> Lease {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(directory.appendingPathComponent("operation.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure.unavailable }
        guard flock(descriptor, (shared ? LOCK_SH : LOCK_EX) | LOCK_NB) == 0 else {
            close(descriptor)
            throw Failure.busy
        }
        // Keep the lock inode: deleting it could allow a second concurrent lock.
        return Lease(descriptor)
    }

    static func withLock<T>(directory: URL, _ operation: () throws -> T) throws -> T {
        let lease = try acquire(directory: directory)
        defer { lease.release() }
        return try operation()
    }
}
