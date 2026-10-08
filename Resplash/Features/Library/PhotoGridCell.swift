import SwiftUI

/// Takes value-type input only, so a change elsewhere in the view model doesn't re-render every cell.
struct PhotoGridCell: View, Equatable {
    let photo: Photo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The colour block reserves the final aspect ratio so layout never jumps as images arrive.
            Color(hex: photo.colorHex)
                .aspectRatio(photo.aspectRatio, contentMode: .fit)
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
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(photo.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .accessibilityElement(children: .combine)
    }
}
