import SwiftUI

/// Caption and photographer attribution shown over the bottom of the pager.
struct PhotoPagerInfoBar: View {
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
        // The caption changes on every page, inside the pager's paging animation. Left to animate,
        // SwiftUI interpolates the old and new text each frame and redraws the bar on the CPU. It should
        // just change.
        .transaction { $0.animation = nil }
    }

    /// "Photo by NAME on Unsplash", with the name linking to the photographer's profile and "Unsplash"
    /// to unsplash.com, as Unsplash's guidelines ask. The name is plain text when there is no profile.
    private var attribution: Text {
        var name = AttributedString(photo.photographer.name)
        name.link = photo.photographer.profileURL
        var unsplash = AttributedString("Unsplash")
        unsplash.link = UnsplashAttribution.homepage
        return Text(AttributedString("Photo by ") + name + AttributedString(" on ") + unsplash)
    }
}
