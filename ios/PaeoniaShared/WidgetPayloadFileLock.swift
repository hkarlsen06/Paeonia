import Darwin
import Foundation

/// App and widget writers share this lock. Keep it outside Widget/, which privacy purges remove.
nonisolated enum WidgetPayloadFileLock {
    static func withExclusiveAccess<Result>(in containerURL: URL, _ body: () throws -> Result) throws -> Result {
        let path = containerURL.appendingPathComponent(".widget-payload.lock").path
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
