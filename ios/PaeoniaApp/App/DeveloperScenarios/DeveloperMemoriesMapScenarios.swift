#if DEBUG
  import CoreLocation
  import ImageIO
  import SwiftUI
  import UniformTypeIdentifiers

  /// "Our places" scenarios, built for the App Store frame: 13 memories with real photos
  /// in 4 countries and 11 cities, and two memories at the Oslo Opera House that open as
  /// a list. The photos are Unsplash photos bundled with Debug builds only
  /// (`MemoriesMapPhotos/`, left out of Release by `release.xcconfig`). The couple is the
  /// test couple, Hjalmar and Elena. No names show on these screens.
  nonisolated extension DeveloperScenario {
    static let memoriesMap: [DeveloperScenario] = [
      memoriesMapTab, memoriesMapPopulated, memoriesMapSelected, memoriesMapCluster, memoriesMapEmpty,
      memoryEditorPlace, memoryPlaceSheet,
    ]

    /// The real path: the paired app on the Memories tab, whose toolbar map button pushes
    /// "Our places".
    static let memoriesMapTab = DeveloperScenario(
      "memories-map-tab", "Memories · tab with places", "The Memories tab with the map fixtures", .memories
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let memoriesMapPopulated = DeveloperScenario(
      "memories-map", "Memories · map", "Our places: 13 memories, 4 countries, 11 cities", .memories
    ) { _ in DeveloperMemoriesMapScenarioView(state: .populated) }
    static let memoriesMapSelected = DeveloperScenario(
      "memories-map-selected", "Memories · map, card", "A selected pin with its card", .memories
    ) { _ in DeveloperMemoriesMapScenarioView(state: .selected) }
    static let memoriesMapCluster = DeveloperScenario(
      "memories-map-cluster", "Memories · map, cluster", "Two memories at one spot, opened as a list", .memories
    ) { _ in DeveloperMemoriesMapScenarioView(state: .cluster) }
    static let memoriesMapEmpty = DeveloperScenario(
      "memories-map-empty", "Memories · map, no places", "Memories without places and the Add place panel",
      .memories
    ) { _ in DeveloperMemoriesMapScenarioView(state: .empty) }
    static let memoryEditorPlace = DeveloperScenario(
      "memory-editor-place", "Memory · editor, photo place", "New memory with a photo taken at Bryggen",
      .memories
    ) { _ in DeveloperMemoryEditorPlaceScenarioView() }
    static let memoryPlaceSheet = DeveloperScenario(
      "memory-place-sheet", "Memory · place sheet", "Place picker with photo places and used places", .memories
    ) { _ in DeveloperMemoryPlaceSheetScenarioView() }
  }

  struct DeveloperMemoriesMapScenarioView: View {
    enum State {
      case populated
      case selected
      case cluster
      case empty
    }

    let state: State
    @SwiftUI.State private var viewModel: MemoriesViewModel

    init(state: State) {
      self.state = state
      DeveloperMemoriesMapFixture.seedPhotos()
      let records = state == .empty
        ? DeveloperMemoriesMapFixture.records(withPlaces: false)
        : DeveloperMemoriesMapFixture.records(withPlaces: true)
      _viewModel = SwiftUI.State(
        initialValue: MemoriesViewModel(
          memoryService: DeveloperScenarioMemoryDataService(records: records),
          operationProvider: DeveloperScenarioOperationProvider(),
          mediaUploader: nil,
          mediaImageCache: nil
        )
      )
    }

    var body: some View {
      NavigationStack {
        if viewModel.hasLoadedOnce {
          MemoriesMapScreen(
            viewModel: viewModel,
            currentUserID: DeveloperScenarioFixture.currentUserID,
            initialSelectedID: state == .selected ? DeveloperMemoriesMapFixture.selectedMemoryID : nil,
            initialCluster: state == .cluster ? viewModel.mapContent.placed.filter {
              DeveloperMemoriesMapFixture.clusterMemoryIDs.contains($0.id)
            } : nil
          )
        }
      }
      .task {
        await viewModel.configure(
          currentUserID: DeveloperScenarioFixture.currentUserID,
          coupleID: DeveloperScenarioFixture.coupleID
        )
      }
    }
  }

  struct DeveloperMemoryEditorPlaceScenarioView: View {
    @State private var draft = MemoryDraft(
      title: "Rain all weekend",
      date: DeveloperScenarioFixture.now,
      note: "We hid in every café on Bryggen and didn't mind the rain one bit.",
      photos: DeveloperMemoriesMapFixture.bryggenPhotoWithLocation().map { [MemoryDraftPhoto(data: $0)] } ?? []
    )

    var body: some View {
      MemoryEditorView(
        draft: $draft,
        allowsPhotos: true,
        knownPlaces: DeveloperMemoriesMapFixture.places,
        onSave: { _, _, _, _, _, _ in false }
      )
    }
  }

  struct DeveloperMemoryPlaceSheetScenarioView: View {
    var body: some View {
      MemoryPlaceSheet(
        photoCoordinates: [DeveloperMemoriesMapFixture.bryggen],
        knownPlaces: Array(DeveloperMemoriesMapFixture.places.prefix(4)),
        isChanging: false
      ) { _ in }
    }
  }

  enum DeveloperMemoriesMapFixture {
    struct Memory {
      let id: String
      let title: String
      let date: String
      let place: MemoryPlace
      let photo: String
      let note: String
      let byPartner: Bool
    }

    static let bryggen = CLLocationCoordinate2D(latitude: 60.3975, longitude: 5.3245)
    static let selectedMemoryID = uuid(4)
    static let clusterMemoryIDs: Set<UUID> = [uuid(1), uuid(2)]

    // Photos are from Unsplash, under the Unsplash License. Photo ids, in order:
    // gjW47r1K63Y, xAnvS-KxCEw, zyoMiko-8yo, GliZKcG2mLY, BLKZfjRaa6Y, LtnPejWDSAY, PA_yJpYt21M,
    // t4x7W1kO37I, kC1-9Snr9hI, zMFxCtkn9vI, WxSzReVMHo0, ljhCEaHYWJ8, A9h1k59QGnY.
    // swiftlint:disable line_length
    static let memories: [Memory] = [
      Memory(id: "1", title: "Coffee after the opera", date: "2026-07-11", place: place("Operastranda", 59.9074, 10.7527, "Oslo", "NO"), photo: "oslo-cafe", note: "Two flat whites and the whole fjord to ourselves.", byPartner: true),
      Memory(id: "2", title: "Up on the opera roof", date: "2026-06-20", place: place("Oslo Opera House", 59.9075, 10.7531, "Oslo", "NO"), photo: "oslo-opera", note: "Barefoot on the marble at sunset.", byPartner: false),
      Memory(id: "3", title: "Picnic at Vigeland", date: "2026-06-07", place: place("Vigeland Park", 59.9270, 10.7009, "Oslo", "NO"), photo: "oslo-frogner", note: "You brought strawberries. I brought the wrong blanket.", byPartner: true),
      Memory(id: "4", title: "Rain all weekend", date: "2026-04-18", place: place("Bryggen", 60.3975, 5.3245, "Bergen", "NO"), photo: "bergen-bryggen", note: "We hid in every café on the wharf.", byPartner: false),
      Memory(id: "5", title: "First ski trip", date: "2026-02-21", place: place("Hovden Alpinsenter", 59.5582, 7.3617, "Hovden", "NO"), photo: "hovden-ski", note: "You fell eleven times and laughed every time.", byPartner: true),
      Memory(id: "6", title: "Northern lights, finally", date: "2026-01-10", place: place("Tromsø", 69.6492, 18.9553, "Tromsø", "NO"), photo: "tromso-aurora", note: "Minus fourteen and worth every minute.", byPartner: false),
      Memory(id: "7", title: "Nyhavn at golden hour", date: "2025-10-04", place: place("Nyhavn", 55.6798, 12.5911, "Copenhagen", "DK"), photo: "copenhagen-nyhavn", note: "Hot dogs on the edge of the canal.", byPartner: true),
      Memory(id: "8", title: "Walking the rainbow", date: "2025-10-02", place: place("ARoS", 56.1537, 10.1997, "Aarhus", "DK"), photo: "aarhus-aros", note: "Every color made the city look different.", byPartner: false),
      Memory(id: "9", title: "Dinner in Trastevere", date: "2025-08-14", place: place("Trastevere", 41.8897, 12.4695, "Rome", "IT"), photo: "rome-trastevere", note: "The best cacio e pepe of our lives.", byPartner: true),
      Memory(id: "10", title: "The view over Florence", date: "2025-08-11", place: place("Piazzale Michelangelo", 43.7629, 11.2650, "Florence", "IT"), photo: "florence-duomo", note: "We stayed until the lights came on.", byPartner: false),
      Memory(id: "11", title: "Lost in Venice", date: "2025-08-08", place: place("Rialto Bridge", 45.4380, 12.3359, "Venice", "IT"), photo: "venice-canal", note: "No map, no plan, no regrets.", byPartner: true),
      Memory(id: "12", title: "Tram 28", date: "2025-05-30", place: place("Alfama", 38.7114, -9.1305, "Lisbon", "PT"), photo: "lisbon-tram", note: "We rode it to the end and back again.", byPartner: false),
      Memory(id: "13", title: "Port by the river", date: "2025-05-27", place: place("Ribeira", 41.1406, -8.6131, "Porto", "PT"), photo: "porto-ribeira", note: "Sunset, a little too much port, and you.", byPartner: true),
    ]
    // swiftlint:enable line_length

    static var places: [MemoryPlace] {
      memories.map(\.place)
    }

    static func records(withPlaces: Bool) -> [MemoryRecord] {
      // Without places, the first five memories wait in the panel.
      let source = withPlaces ? memories : Array(memories.prefix(5))
      return source.map { record(for: $0, withPlace: withPlaces) }
    }

    /// Writes the bundled photos into the memory photo cache under fixed asset ids, so
    /// pins and cards load them like downloaded photos. Synchronous, so the first pin
    /// never asks the server for a photo it doesn't have.
    static func seedPhotos() {
      let directory = MemoryMediaImageDiskCache.defaultDirectoryURL()
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for memory in memories {
        guard let data = photoData(memory.photo) else { continue }
        let file = directory.appendingPathComponent(assetID(memory.photo).uuidString.lowercased())
        try? data.write(to: file, options: .atomic)
      }
    }

    /// The Bryggen photo with GPS metadata added, as if picked from the photo library.
    static func bryggenPhotoWithLocation() -> Data? {
      guard let data = photoData("bergen-bryggen"),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source)
      else { return nil }
      let output = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
      var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
      properties[kCGImagePropertyGPSDictionary] = [
        kCGImagePropertyGPSLatitude: bryggen.latitude,
        kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: bryggen.longitude,
        kCGImagePropertyGPSLongitudeRef: "E",
      ] as [CFString: Any]
      CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
      guard CGImageDestinationFinalize(destination) else { return nil }
      return output as Data
    }

    private static func record(for memory: Memory, withPlace: Bool) -> MemoryRecord {
      let me = DeveloperScenarioFixture.currentUserID
      let partner = DeveloperScenarioFixture.partnerUserID
      let author = memory.byPartner ? partner : me
      let timestamp = MemoryTimeline.parseLocalDate(memory.date) ?? DeveloperScenarioFixture.now
      let index = Int(memory.id) ?? 0
      let id = uuid(index)
      let media = MemoryMediaSnapshot(
        memoryMediaID: UUID(uuidString: "bbbbbbbb-0000-4000-8000-\(String(format: "%012d", index))") ?? UUID(),
        mediaAssetID: assetID(memory.photo),
        ownerUserID: author,
        sortOrder: 1,
        updatedAt: timestamp
      )
      let note = note(memory.note, by: author, at: timestamp)
      return MemoryRecord(
        snapshot: MemorySnapshot(
          ownerUserID: me,
          memoryID: id,
          coupleID: DeveloperScenarioFixture.coupleID,
          title: memory.title,
          memoryDate: memory.date,
          place: withPlace ? memory.place : nil,
          createdByUserID: author,
          lastEditedByUserID: author,
          revision: 1,
          moderationStatus: .visible,
          deletedAt: nil,
          createdAt: timestamp,
          updatedAt: timestamp,
          syncUpdatedAt: timestamp,
          ownNote: memory.byPartner ? nil : note,
          partnerNote: memory.byPartner ? note : nil,
          visibleMemoryMediaIDs: [media.memoryMediaID],
          visibleMediaAssetIDs: [media.mediaAssetID],
          media: [media],
          threadID: nil
        )
      )
    }

    private static func note(_ body: String, by author: UUID, at date: Date) -> MemoryNoteSnapshot {
      MemoryNoteSnapshot(
        noteID: UUID(),
        userID: author,
        body: body,
        revision: 1,
        updatedAt: date,
        deletedAt: nil,
        moderationStatus: .visible
      )
    }

    private static func place(
      _ name: String,
      _ latitude: Double,
      _ longitude: Double,
      _ city: String,
      _ countryCode: String
    ) -> MemoryPlace {
      MemoryPlace(name: name, latitude: latitude, longitude: longitude, city: city, countryCode: countryCode)
    }

    private static func uuid(_ index: Int) -> UUID {
      UUID(uuidString: "aaaaaaaa-0000-4000-8000-\(String(format: "%012d", index))") ?? UUID()
    }

    private static func assetID(_ photo: String) -> UUID {
      let index = memories.firstIndex { $0.photo == photo }.map { $0 + 1 } ?? 0
      return UUID(uuidString: "cccccccc-0000-4000-8000-\(String(format: "%012d", index))") ?? UUID()
    }

    private static func photoData(_ name: String) -> Data? {
      Bundle.main.url(forResource: "scenario-memory-\(name)", withExtension: "jpg")
        .flatMap { try? Data(contentsOf: $0) }
    }
  }
#endif
