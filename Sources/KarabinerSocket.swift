import Foundation
import Darwin

/// Private, ephemeral Karabiner user-command input. Payloads are delivered only
/// on the main queue, and are never logged or persisted by this receiver.
final class KarabinerSocket: @unchecked Sendable {
    let endpoint: String
    private let resources: Resources
    private let source: DispatchSourceRead
    private let receive: (Data) -> Void
    // Recursive because a consumer may close the receiver during delivery.
    private let lock = NSRecursiveLock()
    private var closed = false

    init(receive: @escaping (Data) -> Void) throws {
        let resources = try Resources()
        self.resources = resources
        endpoint = resources.endpoint
        self.receive = receive
        source = DispatchSource.makeReadSource(fileDescriptor: resources.descriptor, queue: .main)
        source.setEventHandler { [weak self] in self?.drain() }
        // Dispatch owns the descriptor until cancellation completes. Closing it
        // earlier could make an already queued event read a reused descriptor.
        source.setCancelHandler { resources.releaseDescriptors() }
        source.resume()
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        source.cancel()
        resources.removeOwnedPaths()
    }

    deinit { close() }

    private func drain() {
        lock.lock()
        defer { lock.unlock() }
        // Limit work per dispatch callback so a producer cannot starve the UI.
        for _ in 0..<32 {
            guard !closed else { return }
            var buffer = [UInt8](repeating: 0, count: 2048)
            var flags: Int32 = 0
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                var vector = iovec(iov_base: bytes.baseAddress, iov_len: bytes.count)
                return withUnsafeMutablePointer(to: &vector) { vector in
                    var message = msghdr()
                    message.msg_iov = vector
                    message.msg_iovlen = 1
                    let count = recvmsg(resources.descriptor, &message, MSG_DONTWAIT)
                    flags = message.msg_flags
                    return count
                }
            }
            if count < 0 {
                if errno == EINTR { continue }
                return
            }
            guard flags & MSG_TRUNC == 0, count <= buffer.count else { continue }
            receive(Data(buffer.prefix(count)))
        }
    }

    private enum Failure: LocalizedError {
        case unavailable(Int32)
        var errorDescription: String? {
            "Karabiner 입력 소켓을 준비하지 못했습니다 (\(code))."
        }
        private var code: Int32 {
            switch self { case .unavailable(let code): return code }
        }
    }

    private final class Resources: @unchecked Sendable {
        let endpoint: String
        let directory: String
        private(set) var descriptor: Int32 = -1
        private var directoryDescriptor: Int32 = -1
        private var directoryIdentity: stat?
        private var socketIdentity: stat?
        private var removedPaths = false
        private let lock = NSLock()
        private static let socketName = "commands.sock"

        init() throws {
            var template = Array("/tmp/dnf-kara.XXXXXX".utf8CString)
            guard let created = mkdtemp(&template) else { throw Failure.unavailable(errno) }
            directory = String(cString: created)
            endpoint = directory + "/" + Self.socketName
            do {
                var directoryStat = stat()
                guard lstat(directory, &directoryStat) == 0 else { throw Failure.unavailable(errno) }
                directoryIdentity = directoryStat
                directoryDescriptor = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard directoryDescriptor >= 0 else { throw Failure.unavailable(errno) }
                var openedDirectory = stat()
                guard fstat(directoryDescriptor, &openedDirectory) == 0 else { throw Failure.unavailable(errno) }
                guard openedDirectory.st_dev == directoryStat.st_dev,
                      openedDirectory.st_ino == directoryStat.st_ino else { throw Failure.unavailable(ESTALE) }
                guard fchmod(directoryDescriptor, 0o700) == 0 else { throw Failure.unavailable(errno) }
                descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
                guard descriptor >= 0 else { throw Failure.unavailable(errno) }
                guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
                      fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else { throw Failure.unavailable(errno) }
                var address = sockaddr_un()
                address.sun_family = sa_family_t(AF_UNIX)
                address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
                let path = Array(endpoint.utf8CString)
                guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw Failure.unavailable(ENAMETOOLONG) }
                withUnsafeMutableBytes(of: &address.sun_path) { bytes in
                    bytes.copyBytes(from: path.map { UInt8(bitPattern: $0) })
                }
                let result = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard result == 0 else { throw Failure.unavailable(errno) }
                var socketStat = stat()
                guard fstatat(directoryDescriptor, Self.socketName, &socketStat, AT_SYMLINK_NOFOLLOW) == 0 else { throw Failure.unavailable(errno) }
                socketIdentity = socketStat
                guard fchmodat(directoryDescriptor, Self.socketName, 0o600, AT_SYMLINK_NOFOLLOW) == 0 else { throw Failure.unavailable(errno) }
            } catch {
                removeOwnedPaths()
                releaseDescriptors()
                throw error
            }
        }

        func removeOwnedPaths() {
            lock.lock()
            defer { lock.unlock() }
            guard !removedPaths else { return }
            removedPaths = true
            if let identity = socketIdentity {
                var current = stat()
                if fstatat(directoryDescriptor, Self.socketName, &current, AT_SYMLINK_NOFOLLOW) == 0,
                   current.st_dev == identity.st_dev, current.st_ino == identity.st_ino {
                    _ = unlinkat(directoryDescriptor, Self.socketName, 0)
                }
            }
            if let identity = directoryIdentity {
                var current = stat()
                if lstat(directory, &current) == 0,
                   current.st_dev == identity.st_dev, current.st_ino == identity.st_ino {
                    _ = rmdir(directory)
                }
            }
        }

        func releaseDescriptors() {
            lock.lock()
            defer { lock.unlock() }
            if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
            if directoryDescriptor >= 0 { Darwin.close(directoryDescriptor); directoryDescriptor = -1 }
        }

        deinit { removeOwnedPaths(); releaseDescriptors() }
    }
}
