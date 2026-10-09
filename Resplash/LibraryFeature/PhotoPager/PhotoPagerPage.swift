import SwiftUI

/// One page of the pager: the photo at its natural aspect ratio, centred on screen.
struct PhotoPagerPage: View {
    let photo: Photo
    let namespace: Namespace.ID
    /// Only joins the shared hero id while opening or closing. At rest (and while paging) the image
    /// gets a throwaway id, so swiping never makes it fly in from a grid cell, and tracks no geometry
    /// at all: a page that is being dragged moves every frame, and tracking its frame cost SwiftUI
    /// dozens of attribute updates per frame for nothing.
    let isHeroSource: Bool

    var body: some View {
        Color(hex: photo.colorHex)
            .aspectRatio(photo.aspectRatio, contentMode: .fit)
            .overlay {
                // The small image is usually already loaded by the grid, so it shows instantly while
                // the larger one downloads on top of it.
                ZStack {
                    remoteImage(photo.thumbnailRequest)
                    remoteImage(photo.fullScreenRequest)
                }
            }
            .clipped()
            .matchedGeometryEffect(
                id: isHeroSource ? photo.id : "\(photo.id)-detached",
                in: namespace,
                properties: isHeroSource ? .frame : []
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(photo.caption)
    }

    private func remoteImage(_ request: ImageRequest) -> some View {
        RemoteImage(request: request) { phase in
            switch phase {
            case .loaded(let image):
                image.resizable().scaledToFill()
            case .loading, .failed:
                Color.clear
            }
        }
    }
}
