import SwiftUI

/// Takes value-type input only, so a change elsewhere in the view model doesn't re-render every cell.
struct PhotoGridCell: View, Equatable {
    
    let photo: Photo
    let namespace: Namespace.ID
    /// True while the pager is showing this photo.
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(photo.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The colour block reserves the final aspect ratio so layout never jumps as images arrive.
    private var placeholder: some View {
        Color(hex: photo.colorHex)
            .aspectRatio(photo.aspectRatio, contentMode: .fit)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if isSelected {
            // The pager owns this photo. Removing the image here and inserting the pager's
            // image in the same update is what lets SwiftUI fly one into the other.
            placeholder
        } else {
            placeholder
                .overlay {
                    AsyncImage(url: photo.smallURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        default:
                            Color.clear
                        }
                    }
                }
                .matchedGeometryEffect(id: photo.id, in: namespace)
        }
    }
}
