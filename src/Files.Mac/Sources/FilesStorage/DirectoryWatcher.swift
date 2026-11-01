import Foundation

public final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    public init() {}
    public func watch(_ url: URL, changed: @escaping @Sendable () -> Void) {
        stop()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link], queue: .main)
        source.setEventHandler(handler: changed)
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }
    public func stop() { source?.cancel(); source = nil }
    deinit { source?.cancel() }
}
