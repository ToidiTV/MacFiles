import Foundation
import Darwin

public enum CancellableCopy {
    public static func copy(_ source: URL, to destination: URL) throws {
        try Task.checkCancellation()
        guard (try? FileManager.default.attributesOfItem(atPath: destination.path)) == nil else { throw StorageError.alreadyExists(destination.lastPathComponent) }
        guard let state = copyfile_state_alloc() else { throw CocoaError(.fileWriteUnknown) }
        defer { copyfile_state_free(state) }
        let callback: copyfile_callback_t = { _, stage, _, _, _, _ in stage == COPYFILE_ERR || Task<Never, Never>.isCancelled ? COPYFILE_QUIT : COPYFILE_CONTINUE }
        guard copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self)) == 0 else { throw POSIXError(.EINVAL) }
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW | COPYFILE_EXCL)
        if copyfile(source.path, destination.path, state, flags) != 0 {
            try Task.checkCancellation()
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: source.path])
        }
        try Task.checkCancellation()
    }
}
