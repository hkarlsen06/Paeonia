import SwiftUI

struct PaeoniaImageViewerControls: View {
    let index: Int?
    let count: Int
    let zoom: PaeoniaImageZoomController
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            if let index, count > 1 {
                Text(.imageViewerPageCounter((index + 1).formatted(), count.formatted()))
                    .accessibilityIdentifier("imageViewer.pageCounter")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PaeoniaSpacing.space12) { pageButtons(index: index) }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(spacing: PaeoniaSpacing.space4) { pageButtons(index: index) }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PaeoniaSpacing.space12) { zoomButtons }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(spacing: PaeoniaSpacing.space4) { zoomButtons }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PaeoniaSpacing.space12) { positionControls }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(spacing: PaeoniaSpacing.space4) { positionControls }
            }
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space8)
        .paeoniaReadableWidth()
    }

    @ViewBuilder
    private func pageButtons(index: Int) -> some View {
        control(.imageViewerPrevious, image: "chevron.left", id: "previous", action: previous)
            .disabled(index == 0)
            .keyboardShortcut(.leftArrow, modifiers: [])
        control(.imageViewerNext, image: "chevron.right", id: "next", action: next)
            .disabled(index == count - 1)
            .keyboardShortcut(.rightArrow, modifiers: [])
    }

    @ViewBuilder
    private var positionControls: some View {
        Label {
            Text(Double(zoom.scale), format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
        } icon: {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
        }
        .accessibilityLabel(Text(.imageViewerZoomLevel))
        .accessibilityValue(Text(Double(zoom.scale), format: .percent.precision(.fractionLength(0))))
        .accessibilityIdentifier("imageViewer.zoomLevel")
        panMenu
    }

    @ViewBuilder
    private var zoomButtons: some View {
        control(.imageViewerZoomOut, image: "minus.magnifyingglass", id: "zoomOut", action: zoom.zoomOut)
            .disabled(!zoom.canZoomOut)
            .keyboardShortcut("-", modifiers: [])
        control(.imageViewerFit, image: "arrow.up.left.and.arrow.down.right", id: "fit", action: zoom.fit)
            .disabled(!zoom.canZoomOut)
            .keyboardShortcut("0", modifiers: [])
        control(.imageViewerZoomIn, image: "plus.magnifyingglass", id: "zoomIn", action: zoom.zoomIn)
            .disabled(!zoom.canZoomIn)
            .keyboardShortcut("+", modifiers: [])
    }

    private var panMenu: some View {
        Menu {
            Button(.imageViewerMoveUp, systemImage: "arrow.up") { zoom.pan(horizontal: 0, vertical: -1) }
                .accessibilityIdentifier("imageViewer.move.up")
            Button(.imageViewerMoveDown, systemImage: "arrow.down") { zoom.pan(horizontal: 0, vertical: 1) }
                .accessibilityIdentifier("imageViewer.move.down")
            Button(.imageViewerMoveLeft, systemImage: "arrow.left") { zoom.pan(horizontal: -1, vertical: 0) }
                .accessibilityIdentifier("imageViewer.move.left")
            Button(.imageViewerMoveRight, systemImage: "arrow.right") { zoom.pan(horizontal: 1, vertical: 0) }
                .accessibilityIdentifier("imageViewer.move.right")
        } label: {
            Label(.imageViewerMove, systemImage: "move.3d")
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(!zoom.canZoomOut)
        .accessibilityIdentifier("imageViewer.move")
    }

    private func control(
        _ title: LocalizedStringResource, image: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label { Text(title).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: image).accessibilityHidden(true)
            }
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, PaeoniaSpacing.space8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("imageViewer.\(id)")
    }
}
