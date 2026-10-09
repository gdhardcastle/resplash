import SwiftUI

/// Full-screen, swipeable pager over the photos a grid view model has loaded: the same data as the
/// grid, laid out one photo per page. Paging near the end loads the next page, as scrolling does.
///
/// The paging is hand-rolled rather than `TabView(.page)`: that is UIKit-backed and ignores the
/// SwiftUI transaction, which stops the selected photo flying in from its grid cell.
struct PhotoPagerView: View {

    @ObservedObject var viewModel: PhotoGridViewModel
    @Binding var selection: Photo.ID
    let namespace: Namespace.ID
    /// True while the selected photo should take part in the grid ↔ pager flight.
    let isHeroActive: Bool
    let onDismiss: () -> Void

    @State private var drag: CGSize = .zero
    @State private var dragAxis: Axis?
    /// Fades in on its own so the flying photo is visible from the first frame of the transition.
    @State private var isBackgroundShown = false

    private static let dismissDistance: CGFloat = 120
    private static let pageAnimation = Animation.spring(response: 0.35, dampingFraction: 0.85)

    private var photos: [Photo] {
        viewModel.photos
    }

    private var selectedIndex: Int {
        photos.firstIndex { $0.id == selection } ?? 0
    }

    private var pageDrag: CGFloat {
        dragAxis == .horizontal ? drag.width : 0
    }

    private var dismissDrag: CGSize {
        dragAxis == .vertical ? drag : .zero
    }

    /// 0 at rest, 1 once dragged far enough that the background has fully faded.
    private var dismissProgress: Double {
        min(1, Double(abs(dismissDrag.height)) / 300)
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .opacity(isBackgroundShown ? 1 - dismissProgress : 0)
                .ignoresSafeArea()

            pager
                .offset(dismissDrag)
                .scaleEffect(1 - dismissProgress * 0.15)

            chrome
                .opacity(isBackgroundShown ? 1 - dismissProgress * 2 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { isBackgroundShown = true }
        }
        .onChange(of: selection) { id in
            if let photo = photos.first(where: { $0.id == id }) {
                viewModel.photoDidAppear(photo)
            }
        }
    }

    private var pager: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let current = selectedIndex
            // Only the neighbours of the current page exist, so a long feed doesn't hold hundreds of
            // live image views.
            let visible = max(0, current - 1)...min(photos.count - 1, current + 1)

            ZStack {
                ForEach(Array(visible), id: \.self) { index in
                    PhotoPagerPage(
                        photo: photos[index],
                        namespace: namespace,
                        isHeroSource: isHeroActive && index == current
                    )
                    .frame(width: width, height: geometry.size.height)
                    .offset(x: CGFloat(index - current) * width + pageDrag)
                    // Shrinking the pager while dismissing would otherwise reveal the neighbours at the edges.
                    .opacity(index == current || dragAxis != .vertical ? 1 : 0)
                }
            }
            .frame(width: width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(pageWidth: width))
        }
        .ignoresSafeArea()
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            if photos.indices.contains(selectedIndex) {
                PhotoPagerInfoBar(photo: photos[selectedIndex])
            }
        }
    }

    /// One gesture for both directions, locked to whichever axis the drag starts along:
    /// horizontal pages by at most one photo, vertical drags the photo away to dismiss.
    private func dragGesture(pageWidth: CGFloat) -> some Gesture {
        // Global space: in the default local space the translation is measured inside the view we are
        // offsetting and scaling, which feeds back into itself and makes the values oscillate.
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                drag = value.translation
            }
            .onEnded { value in
                let axis = dragAxis
                if axis == .vertical, abs(value.translation.height) > Self.dismissDistance {
                    // Leave the photo where it was dragged; the flight back starts from there.
                    onDismiss()
                    return
                }
                let step = axis == .horizontal
                    ? pageStep(translation: value.translation.width, predicted: value.predictedEndTranslation.width, pageWidth: pageWidth)
                    : 0
                // One animation block so the page change and the drag reset move together.
                withAnimation(Self.pageAnimation) {
                    if step != 0 { selection = photos[selectedIndex + step].id }
                    drag = .zero
                    dragAxis = nil
                }
            }
    }

    /// -1, 0 or +1: a deliberate drag or a fast flick moves exactly one page, never more.
    private func pageStep(translation: CGFloat, predicted: CGFloat, pageWidth: CGFloat) -> Int {
        let index = selectedIndex
        let travelled = abs(predicted) > pageWidth * 0.5 ? predicted : translation
        if travelled < -pageWidth * 0.25, index < photos.count - 1 { return 1 }
        if travelled > pageWidth * 0.25, index > 0 { return -1 }
        return 0
    }
}
