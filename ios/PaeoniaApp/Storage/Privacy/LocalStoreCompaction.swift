import Foundation
import SQLite3
import SwiftData

/// SQLite keeps the bytes of a deleted row in the store's free pages and in its
/// write-ahead log (`-wal`) until something overwrites them, so a privacy purge that
/// only deletes rows leaves the deleted text readable on disk. `VACUUM` rewrites the
/// store with only the rows that remain, and a truncating checkpoint copies that into
/// the store file and empties the log.
nonisolated enum LocalStoreCompaction {
    struct Failure: Error {
        let step: String
        let code: Int32
    }

    static func compact(_ container: ModelContainer) throws {
        for configuration in container.configurations where !configuration.isStoredInMemoryOnly {
            try compact(storeAt: configuration.url)
        }
    }

    private static func compact(storeAt url: URL) throws {
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil)
        defer { sqlite3_close(database) }
        guard opened == SQLITE_OK else { throw Failure(step: "open", code: opened) }
        // SwiftData's own connection may be in the middle of a read or write.
        sqlite3_busy_timeout(database, 10_000)

        let vacuumed = sqlite3_exec(database, "VACUUM", nil, nil, nil)
        guard vacuumed == SQLITE_OK else { throw Failure(step: "vacuum", code: vacuumed) }
        let checkpointed = sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        guard checkpointed == SQLITE_OK else { throw Failure(step: "checkpoint", code: checkpointed) }
    }
}
