import SwiftUI

/// A full-screen, read-only history of the couple's daily questions, grouped by the
/// day they belong to (newest first) with a centered date divider between groups.
///
/// It reuses the same read-only question card the Questions tab shows, so a past
/// exchange reads back exactly as it does on the day. Answering never happens here.
struct DailyChallengeHistoryView: View {
    @State private var viewModel: DailyChallengeHistoryViewModel

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.dismiss) private var dismiss

    init(viewModel: DailyChallengeHistoryViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.paeoniaBackgroundPrimary)
                .navigationTitle(Text(.dailyChallengeHistoryTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(Text(.dailyChallengeFlowClose))
                    }
                }
        }
        .preferredColorScheme(.dark)
        .task { await viewModel.load() }
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            // Calm loading surface until the first load settles, so the screen never
            // flashes the empty state before content arrives.
            ProgressView()
                .controlSize(.large)
                .tint(.paeoniaAccentPrimary)
        case .failed:
            failedState
        case .empty:
            emptyState
        case let .content(days):
            timeline(days)
        }
    }

    private func timeline(_ days: [DailyChallengeHistoryDay]) -> some View {
        ScrollView {
            LazyVStack(spacing: PaeoniaSpacing.sectionSpacing) {
                ForEach(days) { day in
                    VStack(spacing: PaeoniaSpacing.space12) {
                        DailyChallengeHistoryDateDivider(date: day.date)

                        ForEach(day.questions) { question in
                            DailyChallengeReadCard(
                                question: question,
                                participants: viewModel.participants
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
        }
        .refreshable { await viewModel.load() }
    }

    private var emptyState: some View {
        PaeoniaEmptyStateView(
            title: .dailyChallengeHistoryEmptyTitle,
            message: .dailyChallengeHistoryEmptyMessage,
            systemImage: "clock.arrow.circlepath"
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    }

    private var failedState: some View {
        PaeoniaEmptyStateView(
            title: .dailyChallengeHistoryLoadFailedTitle,
            message: .dailyChallengeHistoryLoadFailedMessage,
            systemImage: "exclamationmark.triangle"
        ) {
            Button {
                Task { await viewModel.load() }
            } label: {
                Text(.dailyChallengeHistoryRetryButton)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    }

    private func showBanner(for notice: DailyChallengeHistoryViewModel.Notice?) {
        guard let notice else { return }
        bannerCenter.show(
            .error(
                title: String(localized: notice.title),
                message: String(localized: notice.message)
            )
        )
        viewModel.dismissNotice()
    }
}

/// A chat-style date divider: the localized day centered between two thin rules,
/// setting a gentle beat between one day's questions and the next. The date is
/// formatted in UTC so the displayed day matches the couple's local date exactly,
/// regardless of where the reader currently is.
struct DailyChallengeHistoryDateDivider: View {
    let date: Date

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            rule

            Text(date, format: dateFormat)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize()

            rule
        }
        .accessibilityElement(children: .combine)
    }

    private var rule: some View {
        Rectangle()
            .fill(.paeoniaSurfacePressed)
            .frame(height: PaeoniaRadius.strokeDefault)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC") ?? .gmt)
    }
}

#if DEBUG
#Preview {
    DailyChallengeHistoryPreviewHost()
}

private struct DailyChallengeHistoryPreviewHost: View {
    var body: some View {
        DailyChallengeHistoryView(
            viewModel: DailyChallengeHistoryViewModel(
                service: PreviewDailyChallengeService(),
                currentUserID: PreviewDailyChallengeService.userID,
                participants: DailyChallengeParticipants(
                    currentUserID: PreviewDailyChallengeService.userID,
                    currentDisplayName: "Hjalmar",
                    partnerUserID: UUID(),
                    partnerDisplayName: "Oda"
                )
            )
        )
        .environment(PaeoniaBannerCenter())
        .preferredColorScheme(.dark)
    }
}
#endif
