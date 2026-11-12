import Foundation

nonisolated enum RecapNumber: Equatable, Identifiable, Sendable {
    case answeredTogether(Int)
    case drawings(Int)
    case memories(Int, photos: Int)
    case stories(Int)
    case letters(Int)
    case visits(Int, days: Int)
    case gameDays(Int)
    case hearts(Int)
    case longestStreak(Int)

    static func numbers(_ counts: AnniversaryRecap.Counts) -> [RecapNumber] {
        [
            .answeredTogether(counts.answeredTogether),
            .memories(counts.memories, photos: counts.memoryPhotos),
            .drawings(counts.drawings),
            .letters(counts.letters),
            .stories(counts.stories),
            .visits(counts.visits, days: counts.visitDays),
            .gameDays(counts.gameDays),
            .hearts(counts.heartsAllTime),
            .longestStreak(counts.longestStreakAllTime),
        ]
        .filter { $0.value > 0 }
    }

    var id: String {
        switch self {
        case .answeredTogether: "answered"
        case .drawings: "drawings"
        case .memories: "memories"
        case .stories: "stories"
        case .letters: "letters"
        case .visits: "visits"
        case .gameDays: "gameDays"
        case .hearts: "hearts"
        case .longestStreak: "longestStreak"
        }
    }

    var value: Int {
        switch self {
        case let .answeredTogether(count), let .drawings(count), let .memories(count, _), let .stories(count),
             let .letters(count), let .visits(count, _), let .gameDays(count), let .hearts(count),
             let .longestStreak(count):
            count
        }
    }

    var symbol: String {
        switch self {
        case .answeredTogether: "bubble.left.and.text.bubble.right.fill"
        case .drawings: "scribble.variable"
        case .memories: "photo.on.rectangle"
        case .stories: "camera.fill"
        case .letters: "envelope.fill"
        case .visits: "airplane"
        case .gameDays: "gamecontroller.fill"
        case .hearts: "heart.fill"
        case .longestStreak: "flame.fill"
        }
    }

    var label: LocalizedStringResource {
        let one = value == 1
        return switch self {
        case .answeredTogether: one ? .recapNumberAnsweredOne : .recapNumberAnswered
        case .drawings: one ? .recapNumberDrawingsOne : .recapNumberDrawings
        case .memories: one ? .recapNumberMemoriesOne : .recapNumberMemories
        case .stories: one ? .recapNumberStoriesOne : .recapNumberStories
        case .letters: one ? .recapNumberLettersOne : .recapNumberLetters
        case .visits: one ? .recapNumberVisitsOne : .recapNumberVisits
        case .gameDays: one ? .recapNumberGameDaysOne : .recapNumberGameDays
        case .hearts: one ? .recapNumberHeartsOne : .recapNumberHearts
        case .longestStreak: one ? .recapNumberStreakOne : .recapNumberStreak
        }
    }

    var isAllTime: Bool {
        switch self {
        case .hearts, .longestStreak: true
        default: false
        }
    }

    /// The line under the number. The all-time numbers name the day they were counted, so they stay
    /// true when the recap is opened again years later.
    func detail(countedOn: String) -> LocalizedStringResource? {
        switch self {
        case let .memories(_, photos) where photos > 0:
            photos == 1 ? .recapNumberMemoriesPhotosOne : .recapNumberMemoriesPhotos(photos.formatted())
        case let .visits(_, days) where days > 0:
            days == 1 ? .recapNumberVisitsDaysOne : .recapNumberVisitsDays(days.formatted())
        case .hearts:
            .recapNumberAllTime(RecapCopy.date(countedOn))
        case .longestStreak:
            .recapNumberStreakUpTo(RecapCopy.date(countedOn))
        default:
            nil
        }
    }
}
