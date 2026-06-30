import Foundation

extension Array where Element == MemoryMediaSnapshot {
    nonisolated func uniquedByMemoryMediaID() -> [MemoryMediaSnapshot] {
        var seen: Set<UUID> = []
        var result: [MemoryMediaSnapshot] = []
        for item in reversed() where !seen.contains(item.memoryMediaID) {
            seen.insert(item.memoryMediaID)
            result.append(item)
        }
        return result.reversed()
    }

    nonisolated func sortedForMemoryDisplay() -> [MemoryMediaSnapshot] {
        sorted { lhs, rhs in
            if lhs.ownerUserID != rhs.ownerUserID {
                return lhs.ownerUserID.uuidString < rhs.ownerUserID.uuidString
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.memoryMediaID.uuidString < rhs.memoryMediaID.uuidString
        }
    }
}
