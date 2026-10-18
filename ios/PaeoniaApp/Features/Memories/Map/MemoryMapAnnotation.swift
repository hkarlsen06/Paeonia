import MapKit

/// A memory's pin. Pins share one clustering identifier, so MapKit groups nearby ones.
final class MemoryMapAnnotation: NSObject, MKAnnotation {
    let entry: MemoryMapEntry

    init(entry: MemoryMapEntry) {
        self.entry = entry
    }

    var coordinate: CLLocationCoordinate2D {
        entry.place.coordinate
    }

    var memoryID: UUID {
        entry.id
    }
}

extension MKClusterAnnotation {
    /// The memories in a cluster, newest first.
    var memoryEntries: [MemoryMapEntry] {
        memberAnnotations
            .compactMap { ($0 as? MemoryMapAnnotation)?.entry }
            .sorted { lhs, rhs in
                guard lhs.memoryDate == rhs.memoryDate else { return lhs.memoryDate > rhs.memoryDate }
                return lhs.id.uuidString > rhs.id.uuidString
            }
    }
}
