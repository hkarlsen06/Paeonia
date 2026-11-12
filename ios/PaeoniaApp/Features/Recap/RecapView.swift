import SwiftUI

struct RecapView: View {
    let model: RecapViewModel
    let recap: AnniversaryRecap

    @Environment(\.dismiss) private var dismiss
    @State private var page = RecapPage.intro

    private static let pageIndicatorClearance: CGFloat = 48
    @State private var sharing: PaeoniaShareable?

    private var numbers: [RecapNumber] { RecapNumber.numbers(recap.counts) }
    private var moments: [LookBackItem] { model.moments[recap.anniversaryDate] ?? [] }

    private var pages: [RecapPage] {
        [.intro] + numbers.map { .number($0.id) } + (moments.isEmpty ? [] : [.moments]) + [.summary]
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(pages, id: \.self) { page in
                    GeometryReader { proxy in
                        ScrollView {
                            content(for: page)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                                .padding(.vertical, PaeoniaSpacing.space24)
                                .frame(minHeight: proxy.size.height - Self.pageIndicatorClearance)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        // The page ends above the page dots, so no text ever sits under them.
                        .padding(.bottom, Self.pageIndicatorClearance)
                    }
                    .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .background(.paeoniaBackgroundPrimary)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text(.commonDone) }
                        .accessibilityIdentifier("recap.done")
                }
            }
        }
        .presentationBackground(.paeoniaBackgroundPrimary)
        .task(id: recap.anniversaryDate) {
            await model.loadMoments(for: recap)
        }
        // Opened again, from the card or a push, the recap starts on its first page.
        .onDisappear { page = .intro }
        .paeoniaShareSheet(item: $sharing)
    }

    @ViewBuilder
    private func content(for page: RecapPage) -> some View {
        switch page {
        case .intro:
            intro
        case let .number(id):
            if let number = numbers.first(where: { $0.id == id }) {
                RecapNumberPage(number: number, countedOn: recap.countedOn)
            }
        case .moments:
            momentsPage
        case .summary:
            summary
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
            Text(RecapCopy.yearsTitle(recap.years))
                .font(PaeoniaTypography.display)
                .foregroundStyle(.paeoniaTextPrimary)
            Text(RecapCopy.periodLine(recap))
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
            Text(.recapIntroSwipe)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("recap.page.intro")
    }

    private var momentsPage: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            Text(recap.sinceJoined ? .recapMomentsTitleSinceJoined : .recapMomentsTitle)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
            ForEach(Array(moments.enumerated()), id: \.offset) { _, item in
                PaeoniaCard {
                    LookBackContent(
                        item: item,
                        currentUserID: model.people.currentUserID,
                        partnerName: model.people.partnerName,
                        thumbnailLoader: model.thumbnailLoader,
                        showsFullText: true
                    )
                }
            }
        }
        .accessibilityIdentifier("recap.page.moments")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space24) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(RecapCopy.yearsTitle(recap.years))
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(RecapCopy.periodLine(recap))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            RecapNumberList(numbers: numbers, countedOn: recap.countedOn)
            Button {
                PaeoniaHaptics.selection()
                sharing = shareable
            } label: {
                Label { Text(.commonShare) } icon: { Image(systemName: "square.and.arrow.up") }
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .accessibilityIdentifier("recap.share")
        }
        .accessibilityIdentifier("recap.page.summary")
    }

    private var shareable: PaeoniaShareable {
        let card = RecapShareCard(
            title: String(localized: RecapCopy.yearsTitle(recap.years)),
            names: RecapShareCard.names(model.people.currentName, model.people.partnerSharedName),
            period: RecapCopy.periodRange(recap),
            numbers: numbers,
            countedOn: recap.countedOn
        )
        return PaeoniaShareable(title: String(localized: RecapCopy.yearsTitle(recap.years))) {
            PaeoniaShareRenderer.png(card)
        }
    }
}

enum RecapPage: Hashable {
    case intro
    case number(String)
    case moments
    case summary
}

nonisolated enum RecapCopy {
    static func yearsTitle(_ years: Int) -> LocalizedStringResource {
        years == 1 ? .recapTitleYearsOne : .recapTitleYears(years.formatted())
    }

    static func periodLine(_ recap: AnniversaryRecap) -> LocalizedStringResource {
        let start = date(recap.periodStart)
        let end = lastDay(recap)?.formatted(.dateTime.day().month(.wide).year()) ?? recap.periodEnd
        return recap.sinceJoined ? .recapPeriodSinceJoined(start, end) : .recapPeriodYear(start, end)
    }

    /// The days the recap counts, such as "14 September 2025 – 13 September 2026".
    static func periodRange(_ recap: AnniversaryRecap) -> String {
        guard let start = RecapCalendar.displayDate(recap.periodStart), let end = lastDay(recap), start < end
        else { return "\(recap.periodStart) – \(recap.periodEnd)" }
        return (start..<end).formatted(.interval.day().month(.wide).year())
    }

    /// The last day a recap counts: the day before its anniversary, whose content goes in the next one.
    static func lastDay(_ recap: AnniversaryRecap) -> Date? {
        RecapCalendar.displayDate(recap.periodEnd)
            .flatMap { Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: $0) }
    }

    static func date(_ day: String) -> String {
        RecapCalendar.displayDate(day)?.formatted(.dateTime.day().month(.wide).year()) ?? day
    }
}

private struct RecapNumberPage: View {
    let number: RecapNumber
    let countedOn: String

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Image(systemName: number.symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
            Text(number.value.formatted())
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.paeoniaTextPrimary)
            Text(number.label)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
            if let detail = number.detail(countedOn: countedOn) {
                Text(detail)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recap.page.\(number.id)")
    }
}

struct RecapNumberList: View {
    let numbers: [RecapNumber]
    let countedOn: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the label goes under the number, so the icon never covers it.
        let row = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space12))
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            ForEach(numbers) { number in
                row {
                    HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space12) {
                        Image(systemName: number.symbol)
                            .foregroundStyle(.paeoniaAccentPrimary)
                            .frame(minWidth: 24)
                            .accessibilityHidden(true)
                        Text(number.value.formatted())
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaTextPrimary)
                    }
                    Group {
                        if number.isAllTime {
                            let allTime = String(localized: .recapNumberAllTimeShort(RecapCopy.date(countedOn)))
                            Text(verbatim: "\(String(localized: number.label)) · \(allTime)")
                        } else {
                            Text(number.label)
                        }
                    }
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
