import SwiftUI

/// The one place a person shares or saves something they made. It shows the
/// picture as it will leave the app, then offers the share sheet, the words (when
/// the item has them) and Save to Photos. Open it with `paeoniaShareSheet(item:)`
/// or `paeoniaShareToolbar(_:)`.
struct PaeoniaShareSheet: View {
    @State private var model: PaeoniaShareModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(shareable: PaeoniaShareable) {
        _model = State(initialValue: PaeoniaShareModel(shareable: shareable))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: PaeoniaSpacing.space16) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                actions
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space16)
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
            .frame(maxWidth: .infinity)
            .background(.paeoniaBackgroundSecondary)
            .navigationTitle(Text(model.shareable.actionTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(.commonDone)
                    }
                    .accessibilityIdentifier("share.done")
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .task { await model.prepare() }
        .analyticsScreen("share_sheet")
        .alert(Text(.sharePermissionTitle), isPresented: $model.isShowingPermissionAlert) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text(.commonOpenSettings)
            }
            Button(role: .cancel) {} label: {
                Text(.commonCancel)
            }
        } message: {
            Text(.sharePermissionMessage)
        }
        .accessibilityIdentifier("share.sheet")
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        switch model.phase {
        case .preparing:
            ProgressView()
                .controlSize(.large)
                .tint(.paeoniaAccentPrimary)
                .accessibilityLabel(Text(.sharePreparing))
        case let .ready(_, image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                        .strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
                }
                .accessibilityLabel(Text(.sharePreviewAccessibility(model.shareable.title)))
                .accessibilityAddTraits(.isImage)
                .transition(.opacity)
        case .failed:
            VStack(spacing: PaeoniaSpacing.space12) {
                Text(.shareFailedMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await model.prepare() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
                .accessibilityIdentifier("share.retry")
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            if model.shareable.allowsSharing {
                shareButton
                if let text = model.shareable.text {
                    ShareLink(item: text, subject: Text(model.shareable.title)) {
                        Label {
                            Text(.shareAsText)
                        } icon: {
                            Image(systemName: "text.alignleft")
                        }
                    }
                    .buttonStyle(PaeoniaSecondaryButtonStyle())
                    .accessibilityIdentifier("share.text")
                }
            }
            saveButton
            note
        }
        .animation(PaeoniaMotion.stateChange, value: model.saveState)
    }

    @ViewBuilder
    private var shareButton: some View {
        let label = Label {
            Text(.commonShare)
        } icon: {
            Image(systemName: "square.and.arrow.up")
        }
        if case let .ready(image, preview) = model.phase {
            PaeoniaShareImageLink(image: image, preview: preview, title: model.shareable.title) { label }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .accessibilityIdentifier("share.share")
        } else {
            Button {} label: { label }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .disabled(true)
        }
    }

    private var saveButton: some View {
        let isSaved = model.saveState == .saved
        let content = Button {
            Task { await model.save() }
        } label: {
            Label {
                Text(isSaved ? .shareSaved : .shareSave)
            } icon: {
                Image(systemName: isSaved ? "checkmark" : "square.and.arrow.down")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .disabled(!model.isReady || isSaved)
        .accessibilityIdentifier("share.save")
        return Group {
            if model.shareable.allowsSharing {
                content.buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: model.saveState == .saving))
            } else {
                content.buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: model.saveState == .saving))
            }
        }
    }

    @ViewBuilder
    private var note: some View {
        if model.saveState == .failed {
            Text(.shareSaveFailed)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaErrorText)
                .multilineTextAlignment(.center)
        } else if !model.shareable.allowsSharing {
            Text(.shareSaveOnlyNote)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .multilineTextAlignment(.center)
        }
    }
}
