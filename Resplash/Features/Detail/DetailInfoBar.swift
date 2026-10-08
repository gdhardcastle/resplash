import SwiftUI

/// Caption and photographer attribution shown over the bottom of the carousel.
struct DetailInfoBar: View {
    let photo: Photo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(photo.caption)
                .font(.subheadline)
                .lineLimit(3)
            attribution
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var attribution: some View {
        if let url = photo.photographer.profileURL {
            Link("Photo by \(photo.photographer.name) on Unsplash", destination: url)
        } else {
            Text("Photo by \(photo.photographer.name) on Unsplash")
        }
    }
}
