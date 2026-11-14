import SwiftUI

struct PiccanteTurnButtons: View {
    let viewModel: PiccanteViewModel
    let game: RemotePiccanteGame

    var body: some View {
        switch viewModel.boardMode {
        case .bite: biteButtons
        case .sniff(let target): sniffButtons(target: target)
        }
    }

    @ViewBuilder private var biteButtons: some View {
        if viewModel.showsBiteHint {
            Text(.piccanteBiteHint).foregroundStyle(.paeoniaTextSecondary)
        }
        Button {
            Task { await viewModel.act(.bite) }
        } label: {
            Text(.piccanteBiteAction)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!viewModel.canAct || viewModel.selected == nil)
        .accessibilityIdentifier("piccante.bite")
        if game.mySniff == nil {
            Button {
                viewModel.startSniff()
            } label: {
                Label {
                    Text(.piccanteSniffAction)
                } icon: {
                    Image(systemName: "nose")
                }
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .disabled(!viewModel.canStartSniff)
            .accessibilityIdentifier("piccante.sniff")
        }
    }
    @ViewBuilder private func sniffButtons(target: Int?) -> some View {
        Text(.piccanteSniffHint(viewModel.partnerName)).foregroundStyle(.paeoniaTextSecondary)
        Button {
            Task { await viewModel.confirmSniff() }
        } label: {
            Text(.piccanteSniffConfirm)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(target == nil || !viewModel.canAct)
        .accessibilityIdentifier("piccante.sniff.confirm")
        Button {
            viewModel.cancelSniff()
        } label: {
            Text(.commonCancel)
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .accessibilityIdentifier("piccante.sniff.cancel")
    }
}
