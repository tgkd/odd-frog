import Foundation

public final class DirectoryWatcher: @unchecked Sendable {
    public let queue: DispatchQueue
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var debounce: DispatchWorkItem?
    private var onChange: (@Sendable () -> Void)?
    private let debounceInterval: TimeInterval

    public init(queue: DispatchQueue = DispatchQueue(label: "odd-frog.directory-watcher"), debounce: TimeInterval = 0.3) {
        self.queue = queue
        self.debounceInterval = debounce
    }

    public func watch(_ directories: [URL], onChange: @escaping @Sendable () -> Void) {
        queue.async {
            self.onChange = onChange
            let wanted = Set(directories.map { $0.standardizedFileURL.path })
            for (path, source) in self.sources where !wanted.contains(path) {
                source.cancel()
                self.sources[path] = nil
            }
            for path in wanted where self.sources[path] == nil {
                self.sources[path] = self.makeSource(path: path)
            }
        }
    }

    public func stop() {
        queue.sync {
            sources.values.forEach { $0.cancel() }
            sources.removeAll()
            onChange = nil
        }
    }

    private func makeSource(path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .revoke, .extend], queue: queue)
        source.setEventHandler { [weak self] in self?.fire(path: path) }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func fire(path: String) {
        var info = stat()
        if stat(path, &info) != 0 {
            sources[path]?.cancel()
            sources[path] = nil
        }
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        debounce = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
