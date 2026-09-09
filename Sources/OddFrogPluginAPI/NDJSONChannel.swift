import Foundation
import Darwin

/// Bounded framing shared by the Swift SDK and host. stderr is never part of this channel.
public final class NDJSONChannel: @unchecked Sendable {
    public let messages: AsyncThrowingStream<PluginEnvelope, any Error>
    private let continuation: AsyncThrowingStream<PluginEnvelope, any Error>.Continuation
    private let input: FileHandle
    private let output: FileHandle
    private let inputFD: Int32
    private let outputFD: Int32
    private let lock = NSLock()
    private let writeLock = NSLock()
    private let writer = DispatchQueue(label: "odd-frog.protocol.writer")
    private var buffer = Data()
    private var closed = false
    private var outputClosed = false
    public init(input: FileHandle, output: FileHandle) {
        self.input = input; self.output = output
        inputFD = input.fileDescriptor; outputFD = output.fileDescriptor
        (messages, continuation) = AsyncThrowingStream.makeStream()
        input.readabilityHandler = { [weak self] _ in self?.receive() }
    }
    private func receive() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        do {
            var bytes = [UInt8](repeating: 0, count: 65536)
            var count = Darwin.read(inputFD, &bytes, bytes.count)
            while count < 0 && errno == EINTR { count = Darwin.read(inputFD, &bytes, bytes.count) }
            guard count >= 0 else { throw RPCError("protocol", "Provider pipe read failed: \(String(cString: strerror(errno))).") }
            let data = Data(bytes.prefix(count))
            if data.isEmpty {
                if !buffer.isEmpty { throw RPCError("protocol", "Incomplete JSON message at EOF.") }
                closed = true; input.readabilityHandler = nil; continuation.finish(); return
            }
            buffer.append(data)
            while let end = buffer.firstIndex(of: 10) {
                guard end <= PluginProtocol.maxBytes else { throw RPCError("protocol", "Message exceeds four MiB.") }
                let line = buffer.prefix(upTo: end)
                let envelope = try PluginProtocol.decoder().decode(PluginEnvelope.self, from: line)
                try envelope.validate()
                continuation.yield(envelope)
                buffer.removeSubrange(...end)
            }
            guard buffer.count <= PluginProtocol.maxBytes else { throw RPCError("protocol", "Message exceeds four MiB.") }
        } catch {
            closed = true; input.readabilityHandler = nil
            continuation.finish(throwing: RPCError("protocol", "Invalid provider output: \(error)"))
        }
    }
    public func send(_ envelope: PluginEnvelope) throws {
        try envelope.validate()
        var data = try PluginProtocol.encoder().encode(envelope)
        guard data.count <= PluginProtocol.maxBytes else { throw RPCError("protocol", "Message exceeds four MiB.") }
        data.append(10)
        writeLock.lock(); defer { writeLock.unlock() }
        guard !outputClosed else { throw RPCError("protocol", "Provider input is closed.") }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(outputFD, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw RPCError("protocol", "Provider pipe write failed: \(String(cString: strerror(errno))).") }
                offset += count
            }
        }
    }
    /// Never block an actor's executor on an unresponsive provider's stdin.
    public func enqueue(_ envelope: PluginEnvelope, onError: @escaping @Sendable (any Error) -> Void) {
        writer.async { [self] in
            do { try send(envelope) } catch { onError(error) }
        }
    }
    public func close() {
        lock.lock(); defer { lock.unlock() }
        closed = true; input.readabilityHandler = nil; continuation.finish()
        try? input.close()
        // FileHandle raises Objective-C exceptions for writes after close. Synchronize both
        // closing and queued sends; killing the child first releases a blocked pipe write.
        writeLock.lock(); defer { writeLock.unlock() }
        outputClosed = true; try? output.close()
    }
}
