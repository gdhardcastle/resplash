import Foundation

/// Lets the Library scroll a grid without changing any state a view reads.
///
/// The grid's scroll position used to follow `selectedID`, so every time the pager reported a page, the
/// Library and the grid re-ran their bodies and re-laid out every photo, just to scroll. This is a plain
/// reference, not `@State` or `ObservableObject`: calling it re-evaluates nothing, it only scrolls. The
/// grid registers how to scroll once it is on screen.
final class GridScroller {

    var scrollTo: ((Photo.ID) -> Void)?
    private var lastTarget: Photo.ID?

    /// Scrolls to `id` unless the grid is already there. Returns whether it scrolled.
    @discardableResult
    func scroll(to id: Photo.ID) -> Bool {
        guard id != lastTarget, let scrollTo else { return false }
        lastTarget = id
        scrollTo(id)
        return true
    }

    /// Records where the grid already is, such as the cell that was just tapped.
    func reset(to id: Photo.ID) {
        lastTarget = id
    }
}
