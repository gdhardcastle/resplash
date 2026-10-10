import XCTest

/// The main flows, end to end, with real touches. The app is launched with `-ui-testing`, which gives
/// it a fixed set of eight photos (see `StubPhotoRepository`), so the tests need no network or access
/// key and see the same screen every time.
@MainActor
final class LibraryUITests: XCTestCase {

    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testTheFeedShowsPhotos() {
        XCTAssertTrue(photoCell("A snow-capped mountain at sunrise").waitForExistence(timeout: 10))
        XCTAssertTrue(photoCell("A red bicycle leaning on a blue wall").exists)
    }

    func testOpeningAPhotoShowsItsPhotographer() {
        openPhoto("A snow-capped mountain at sunrise")
        XCTAssertTrue(element(labelBeginningWith: "Photo by Alex Rivera").waitForExistence(timeout: 5))
    }

    func testSwipingTheViewerMovesToTheNextPhoto() {
        openPhoto("A snow-capped mountain at sunrise")
        app.swipeLeft()
        XCTAssertTrue(element(labelBeginningWith: "Photo by Sam Okafor").waitForExistence(timeout: 5),
                      "The second photo's photographer did not appear after swiping")
    }

    func testClosingTheViewerReturnsToTheGrid() {
        openPhoto("A snow-capped mountain at sunrise")
        app.buttons["Close"].tap()
        XCTAssertTrue(photoCell("A snow-capped mountain at sunrise").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Close"].exists)
    }

    func testSearchNarrowsTheGridToMatchingPhotos() {
        search(for: "mountain")
        XCTAssertTrue(photoCell("A snow-capped mountain at sunrise").waitForExistence(timeout: 5))
        XCTAssertFalse(photoCell("A red bicycle leaning on a blue wall").exists)
    }

    func testSearchWithNoMatchesShowsAMessage() {
        search(for: "zebra")
        XCTAssertTrue(app.staticTexts["No results for “zebra”"].waitForExistence(timeout: 5))
    }

    // MARK: Helpers

    private func search(for text: String) {
        let field = app.searchFields["Search photos"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text)
    }

    private func openPhoto(_ caption: String) {
        let cell = photoCell(caption)
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "The feed did not load")
        cell.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5), "The viewer did not open")
    }

    /// A grid cell is a button whose combined label includes the photo's caption.
    private func photoCell(_ caption: String) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", caption)).firstMatch
    }

    private func element(labelBeginningWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }
}
