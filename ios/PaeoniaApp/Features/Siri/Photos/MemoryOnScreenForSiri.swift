import AppIntents
import SwiftUI

extension View {
    /// Tells Siri which memory is on screen, so "this memory" means it, and shows the photo
    /// Siri's "open this photo" asked for. `initial` covers a request that arrived before the
    /// memory's screen did.
    func memoryOnScreenForSiri(
        _ memoryID: UUID,
        title: String?,
        viewModel: MemoriesViewModel,
        shownPhotoID: Binding<UUID?>
    ) -> some View {
        onChange(of: viewModel.requestedPhotoID, initial: true) { _, photoID in
            guard let photoID else { return }
            viewModel.requestedPhotoID = nil
            shownPhotoID.wrappedValue = photoID
        }
        .userActivity("no.paeonia.app.memory") { activity in
            activity.title = title
            activity.appEntityIdentifier = EntityIdentifier(for: MemoryAlbumEntity.self, identifier: memoryID)
        }
    }
}
