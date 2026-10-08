import Combine
import SwiftUI

/// Coordinates the grid ↔ carousel hand-off: which photo is open, and whether it is mid-flight.
///
/// The carousel's page only joins the shared hero id while opening or closing; at rest it uses a
/// throwaway id, so paging never makes a photo fly in from a grid cell.
@MainActor
final class HeroTransition: ObservableObject {
    private static let duration = 0.4
    private static let animation = Animation.timingCurve(0.25, 0.8, 0.25, 1, duration: duration)

    /// The photo open in the carousel. `nil` means the grid is showing. Settable so paging can move it.
    @Published var selectedID: Photo.ID?
    /// True only while the selected photo is flying between grid and carousel.
    @Published private(set) var isActive = false

    private var task: Task<Void, Never>?

    func present(_ photo: Photo) {
        task?.cancel()
        isActive = true
        withAnimation(Self.animation) { selectedID = photo.id }
        // Once the flight lands, detach the page from the grid so paging can't trigger another one.
        task = Task {
            try? await Task.sleep(for: .seconds(Self.duration + 0.1))
            guard !Task.isCancelled else { return }
            isActive = false
        }
    }

    func dismiss() {
        task?.cancel()
        task = Task {
            // Rejoin the hero id first, in its own update, so the flight back has a matching pair.
            isActive = true
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            withAnimation(Self.animation) { selectedID = nil }
        }
    }
}
