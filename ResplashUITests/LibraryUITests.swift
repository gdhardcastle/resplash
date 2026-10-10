import XCTest

/// The main flows, end to end, with real touches. The app is launched with `-ui-testing` and the photos in
/// `TestPhotos`, so the tests need no network or access key and see the same screen every time.
@MainActor
final class LibraryUITests: XCTestCase {

    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITEST_PHOTOS"] = TestPhotos.json
        app.launch()
    }

    func testTheFeedShowsPhotos() {
        XCTAssertTrue(photoCell(TestPhotos.mountain).waitForExistence(timeout: 10))
        XCTAssertTrue(photoCell(TestPhotos.bicycle).exists)
    }

    func testOpeningAPhotoShowsItsPhotographer() {
        openPhoto(TestPhotos.mountain)
        XCTAssertTrue(element(labelBeginningWith: "Photo by \(TestPhotos.mountain.photographer)").waitForExistence(timeout: 5))
    }

    func testSwipingTheViewerMovesToTheNextPhoto() {
        openPhoto(TestPhotos.mountain)
        app.swipeLeft()
        XCTAssertTrue(element(labelBeginningWith: "Photo by \(TestPhotos.bicycle.photographer)").waitForExistence(timeout: 5),
                      "The second photo's photographer did not appear after swiping")
    }

    func testClosingTheViewerReturnsToTheGrid() {
        openPhoto(TestPhotos.mountain)
        app.buttons["Close"].tap()
        XCTAssertTrue(photoCell(TestPhotos.mountain).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Close"].exists)
    }

    func testSearchNarrowsTheGridToMatchingPhotos() {
        search(for: "mountain")
        XCTAssertTrue(photoCell(TestPhotos.mountain).waitForExistence(timeout: 5))
        XCTAssertFalse(photoCell(TestPhotos.bicycle).exists)
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

    private func openPhoto(_ photo: TestPhotos.Photo) {
        let cell = photoCell(photo)
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "The feed did not load")
        cell.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5), "The viewer did not open")
    }

    /// A grid cell is a button whose combined label includes the photo's caption.
    private func photoCell(_ photo: TestPhotos.Photo) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", photo.caption)).firstMatch
    }

    private func element(labelBeginningWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }
}
