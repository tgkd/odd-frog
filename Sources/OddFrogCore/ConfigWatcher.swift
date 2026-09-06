import Foundation

public final class ConfigWatcher: @unchecked Sendable {
    public let path: URL
    public let queue: DispatchQueue
    private var lastContents: Data?
    private var onChange: (@Sendable (Data) -> Void)?

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var directoryInode: ino_t = 0
    private var fileInode: ino_t = 0
    private var debounce: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private let debounceInterval: TimeInterval
    private let retryInterval: TimeInterval

    private static var mask: DispatchSource.FileSystemEvent { [.write, .rename, .delete, .revoke, .extend, .attrib] }

    public init(path: URL, queue: DispatchQueue = DispatchQueue(label: "odd-frog.config-watcher"), debounce: TimeInterval = 0.2, retry: TimeInterval = 1.0) {
        self.path = path
        self.queue = queue
        self.debounceInterval = debounce
        self.retryInterval = retry
    }

    public func start(lastContents: Data?, onChange: @escaping @Sendable (Data) -> Void) {
        queue.async {
            self.lastContents = lastContents
            self.onChange = onChange
            self.bindDirectory()
            self.bindFile()
        }
    }

    public func markApplied(_ contents: Data) {
        queue.async { self.lastContents = contents }
    }

    public func stop() {
        queue.sync {
            directorySource?.cancel()
            fileSource?.cancel()
            directorySource = nil
            fileSource = nil
            debounce?.cancel()
            retry?.cancel()
            onChange = nil
        }
    }

    private func bindDirectory() {
        directorySource?.cancel()
        directorySource = nil
        guard let (source, inode) = makeSource(for: path.deletingLastPathComponent()) else {
            scheduleRetry()
            return
        }
        directoryInode = inode
        directorySource = source
    }

    private func bindFile() {
        fileSource?.cancel()
        fileSource = nil
        guard let (source, inode) = makeSource(for: path) else {
            scheduleRetry()
            return
        }
        fileInode = inode
        fileSource = source
    }

    private func makeSource(for url: URL) -> (DispatchSourceFileSystemObject, ino_t)? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            close(fd)
            return nil
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: Self.mask, queue: queue)
        source.setEventHandler { [weak self] in self?.scheduleCheck() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return (source, info.st_ino)
    }

    private func scheduleRetry() {
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        retry = work
        queue.asyncAfter(deadline: .now() + retryInterval, execute: work)
    }

    private func scheduleCheck() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        debounce = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func check() {
        if let inode = Self.inode(of: path.deletingLastPathComponent()) {
            if directorySource == nil || inode != directoryInode { bindDirectory() }
        } else {
            directorySource?.cancel()
            directorySource = nil
            scheduleRetry()
            return
        }
        if let inode = Self.inode(of: path) {
            if fileSource == nil || inode != fileInode { bindFile() }
        } else {
            fileSource?.cancel()
            fileSource = nil
            scheduleRetry()
            return
        }
        guard let data = try? Data(contentsOf: path) else {
            scheduleRetry()
            return
        }
        if data != lastContents {
            lastContents = data
            onChange?(data)
        }
    }

    private static func inode(of url: URL) -> ino_t? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return info.st_ino
    }
}
