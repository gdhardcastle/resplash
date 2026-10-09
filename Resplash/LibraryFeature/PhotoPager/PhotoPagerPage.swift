import SwiftUI

/// One page of the pager: the photo at its natural aspect ratio, centred on screen.
struct PhotoPagerPage: View {
    let photo: Photo
    let namespace: Namespace.ID
    /// Only joins the shared hero id while opening or closing. At rest (and while paging) the image
    /// gets a throwaway id, so swiping never makes it fly in from a grid cell.
    let isHeroSource: Bool

    var body: some View {
        Color(hex: photo.colorHex)
            .aspectRatio(photo.aspectRatio, contentMode: .fit)
            .overlay {
                // The small image is usually already loaded by the grid, so it shows instantly while
                // the larger one downloads on top of it.
                ZStack {
                    remoteImage(photo.smallURL)
                    remoteImage(photo.regularURL)
                }
            }
            .clipped()
            .matchedGeometryEffect(id: isHeroSource ? photo.id : "\(photo.id)-detached", in: namespace)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(photo.caption)
    }

    private func remoteImage(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
    }
}
