import Foundation
import Darwin

private func checkSocket(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

private func sendSocket(_ data: Data, to endpoint: String) -> Int {
    let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
    guard fd >= 0 else { return -1 }
    defer { Darwin.close(fd) }
    // Darwin defaults to a 2,048-byte sender limit; raise only this test sender.
    var sendBuffer: Int32 = 8192
    guard setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sendBuffer, socklen_t(MemoryLayout<Int32>.size)) == 0 else { return -1 }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(endpoint.utf8CString)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
            data.withUnsafeBytes { sendto(fd, $0.baseAddress, $0.count, 0, address, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
}

private func pumpSocket(until predicate: () -> Bool, timeout: TimeInterval = 1) {
    let end = Date(timeIntervalSinceNow: timeout)
    while !predicate() && Date() < end {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
    }
}

@main struct KarabinerSocketTests {
    static func main() throws {
        // Missing receive delivery or the wrong queue must fail this real datagram test.
        var packets: [Data] = []
        let receiver = try KarabinerSocket { data in
            checkSocket(Thread.isMainThread, "delivery runs on the main queue")
            packets.append(data)
        }
        let endpoint = receiver.endpoint
        let directory = URL(fileURLWithPath: endpoint).deletingLastPathComponent().path
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory)
        let socketAttributes = try FileManager.default.attributesOfItem(atPath: endpoint)
        checkSocket((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700, "private directory permissions")
        checkSocket((socketAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "private socket permissions")
        checkSocket(endpoint.utf8.count < 104, "Darwin Unix address fits")
        checkSocket(sendSocket(Data("press:57".utf8), to: endpoint) == 8, "send datagram to bound endpoint")
        pumpSocket(until: { packets.count == 1 })
        checkSocket(packets == [Data("press:57".utf8)], "payload arrives unchanged")

        // A truncated packet must not be interpreted as a valid prefix.
        checkSocket(sendSocket(Data(repeating: 120, count: 2049), to: endpoint) == 2049, "oversized test datagram queued")
        pumpSocket(until: { false }, timeout: 0.03)
        checkSocket(packets.count == 1, "oversized datagram produces no callback")
        checkSocket(sendSocket(Data(repeating: 121, count: 2048), to: endpoint) == 2048, "maximum valid datagram queued")
        pumpSocket(until: { packets.count >= 2 })
        checkSocket(packets.count == 2 && packets[1] == Data(repeating: 121, count: 2048), "oversized datagram dropped; boundary packet delivered")

        // Closing from inside delivery must prevent the following queued packet.
        var reentrant: KarabinerSocket?
        var deliveries = 0
        reentrant = try KarabinerSocket { _ in deliveries += 1; reentrant?.close() }
        let reentrantEndpoint = reentrant!.endpoint
        checkSocket(sendSocket(Data([1]), to: reentrantEndpoint) == 1, "queue first reentrant packet")
        checkSocket(sendSocket(Data([2]), to: reentrantEndpoint) == 1, "queue second reentrant packet")
        pumpSocket(until: { deliveries > 0 })
        pumpSocket(until: { false }, timeout: 0.03)
        checkSocket(deliveries == 1, "reentrant close stops further delivery")
        reentrant = nil

        receiver.close()
        receiver.close()
        checkSocket(!FileManager.default.fileExists(atPath: endpoint), "close removes own endpoint")
        checkSocket(!FileManager.default.fileExists(atPath: directory), "close removes own directory")
        checkSocket(sendSocket(Data([1]), to: endpoint) == -1, "closed endpoint rejects new datagrams")

        // Queued reads after concurrent close must not touch reused descriptors.
        var lateDeliveries = 0
        let pending = try KarabinerSocket { _ in lateDeliveries += 1 }
        let pendingDirectory = URL(fileURLWithPath: pending.endpoint).deletingLastPathComponent()
        checkSocket(sendSocket(Data([3]), to: pending.endpoint) == 1, "queue datagram before concurrent close")
        DispatchQueue.concurrentPerform(iterations: 16) { _ in pending.close() }
        var reusedDescriptors: [Int32] = []
        for _ in 0..<64 { reusedDescriptors.append(open("/dev/null", O_RDONLY)) }
        pumpSocket(until: { false }, timeout: 0.03)
        for fd in reusedDescriptors where fd >= 0 { Darwin.close(fd) }
        checkSocket(lateDeliveries == 0, "cancellation prevents queued reads after close")
        checkSocket(!FileManager.default.fileExists(atPath: pendingDirectory.path), "concurrent close removes resources once")

        var automatic: KarabinerSocket? = try KarabinerSocket { _ in }
        let automaticDirectory = URL(fileURLWithPath: automatic!.endpoint).deletingLastPathComponent()
        automatic = nil
        checkSocket(!FileManager.default.fileExists(atPath: automaticDirectory.path), "deinit closes receiver")

        // Replacing a pathname must never let teardown remove a foreign file.
        let replaced = try KarabinerSocket { _ in }
        let replacedEndpoint = replaced.endpoint
        let replacedDirectory = URL(fileURLWithPath: replacedEndpoint).deletingLastPathComponent()
        checkSocket(unlink(replacedEndpoint) == 0, "unlink owned endpoint for replacement test")
        try Data("foreign".utf8).write(to: URL(fileURLWithPath: replacedEndpoint))
        replaced.close()
        let foreignData = try Data(contentsOf: URL(fileURLWithPath: replacedEndpoint))
        checkSocket(foreignData == Data("foreign".utf8), "close preserves replacement file")
        try FileManager.default.removeItem(at: replacedDirectory)

        let moved = try KarabinerSocket { _ in }
        let originalDirectory = URL(fileURLWithPath: moved.endpoint).deletingLastPathComponent()
        let movedDirectory = originalDirectory.appendingPathExtension("moved")
        try FileManager.default.moveItem(at: originalDirectory, to: movedDirectory)
        try FileManager.default.createDirectory(at: originalDirectory, withIntermediateDirectories: false)
        let replacement = URL(fileURLWithPath: moved.endpoint)
        try Data("replacement directory".utf8).write(to: replacement)
        moved.close()
        let replacementData = try Data(contentsOf: replacement)
        checkSocket(replacementData == Data("replacement directory".utf8), "close preserves replacement directory and its contents")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: movedDirectory.path)
        checkSocket(remaining.isEmpty, "cleanup uses original directory descriptor")
        try FileManager.default.removeItem(at: movedDirectory)
        try FileManager.default.removeItem(at: originalDirectory)
        print("PASS: private Karabiner datagrams, bounds, main-queue delivery and ownership-safe cleanup")
    }
}
