#if DEBUG
  import Foundation

  enum DeveloperMemoryCardFixture {
    private struct Example {
      let title: String
      let note: String
      let photoIndices: [Int]
      var showsPlace = false
      var isDirty = false
    }

    private static let longNote = """
      Vi skulle egentlig bare si god natt, men ble sittende og tegne og snakke om alt som hadde skjedd den dagen. \
      Plutselig var det langt over midnatt. Jeg ville ikke at kvelden skulle ta slutt, og du fant på stadig nye \
      ting vi kunne tegne sammen.
      """

    static func records() -> [MemoryRecord] {
      DeveloperMemoriesMapFixture.seedPhotos()
      let photos = DeveloperMemoriesMapFixture.records(withPlaces: true)
      let examples = [
        Example(title: "Bare oss", note: longNote, photoIndices: [0, 1, 2], showsPlace: true, isDirty: true),
        Example(
          title: "Den kvelden vi glemte tiden og bare tegnet",
          note: longNote,
          photoIndices: [1]
        ),
        Example(
          title: "Den kvelden vi glemte tiden og tegnet sammen helt til det nesten var morgen igjen, "
            + "og vi fremdeles hadde tusen små historier vi ville fortelle hverandre",
          note: longNote,
          photoIndices: [2]
        ),
        Example(title: "En helt vanlig tirsdag", note: longNote, photoIndices: [], showsPlace: true),
        Example(title: "God natt", note: "Bare fem minutter til.", photoIndices: [4]),
      ]
      return zip(photos, examples).map { source, example in
        record(from: source.snapshot, example: example, photos: photos)
      }
    }

    private static func record(
      from source: MemorySnapshot,
      example: Example,
      photos: [MemoryRecord]
    ) -> MemoryRecord {
      let media = example.photoIndices.enumerated().map { offset, index in
        MemoryMediaSnapshot(
          memoryMediaID: UUID(),
          mediaAssetID: photos[index].snapshot.visibleMediaAssetIDs[0],
          ownerUserID: source.createdByUserID,
          sortOrder: offset,
          updatedAt: source.updatedAt
        )
      }
      let note = note(example.note, source: source)
      return MemoryRecord(
        snapshot: MemorySnapshot(
          ownerUserID: source.ownerUserID,
          memoryID: source.memoryID,
          coupleID: source.coupleID,
          title: example.title,
          memoryDate: source.memoryDate,
          place: example.showsPlace ? source.place : nil,
          createdByUserID: source.createdByUserID,
          lastEditedByUserID: source.lastEditedByUserID,
          revision: source.revision,
          moderationStatus: source.moderationStatus,
          deletedAt: nil,
          createdAt: source.createdAt,
          updatedAt: source.updatedAt,
          syncUpdatedAt: source.syncUpdatedAt,
          ownNote: source.createdByUserID == source.ownerUserID ? note : nil,
          partnerNote: source.createdByUserID == source.ownerUserID ? nil : note,
          visibleMemoryMediaIDs: media.map(\.memoryMediaID),
          visibleMediaAssetIDs: media.map(\.mediaAssetID),
          media: media,
          threadID: nil
        ),
        syncStatus: example.isDirty ? .dirty : .clean
      )
    }

    private static func note(_ body: String, source: MemorySnapshot) -> MemoryNoteSnapshot {
      MemoryNoteSnapshot(
        noteID: UUID(),
        userID: source.createdByUserID,
        body: body,
        revision: 1,
        updatedAt: source.updatedAt,
        deletedAt: nil,
        moderationStatus: .visible
      )
    }
  }
#endif
