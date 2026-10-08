import Foundation
import Testing
@testable import Resplash

struct MasonryLayoutTests {
    private func photo(_ id: String, aspectRatio: Double) -> Photo {
        Photo(
            id: id,
            caption: id,
            width: Int(aspectRatio * 1000),
            height: 1000,
            colorHex: "#808080",
            smallURL: URL(string: "https://example.com/\(id)")!,
            regularURL: URL(string: "https://example.com/\(id)")!,
            photographer: Photographer(name: "Jane", profileURL: nil)
        )
    }

    private func ids(_ columns: [[Photo]]) -> [[String]] {
        columns.map { $0.map(\.id) }
    }

    @Test func emptyInputGivesEmptyColumns() {
        #expect(MasonryLayout.columns(for: []).map(\.count) == [0, 0])
    }

    @Test func alternatesWhenPhotosAreTheSameHeight() {
        let photos = (1...4).map { photo(String($0), aspectRatio: 1) }
        #expect(ids(MasonryLayout.columns(for: photos)) == [["1", "3"], ["2", "4"]])
    }

    @Test func fillsTheShorterColumn() {
        // A tall photo (aspect 0.5) in column 0 means the next two short ones both go to column 1.
        let photos = [photo("tall", aspectRatio: 0.5), photo("a", aspectRatio: 2), photo("b", aspectRatio: 2)]
        #expect(ids(MasonryLayout.columns(for: photos)) == [["tall"], ["a", "b"]])
    }

    @Test func everyPhotoAppearsExactlyOnceInOrder() {
        let photos = (1...20).map { photo(String($0), aspectRatio: Double($0 % 5 + 1) / 3) }
        let columns = MasonryLayout.columns(for: photos)
        #expect(Set(columns.flatMap { $0.map(\.id) }) == Set(photos.map(\.id)))
        #expect(columns.flatMap { $0 }.count == photos.count)
        for column in columns {
            let order = column.compactMap { p in photos.firstIndex { $0.id == p.id } }
            #expect(order == order.sorted())
        }
    }

    @Test func appendingPhotosNeverMovesExistingOnes() {
        let photos = (1...12).map { photo(String($0), aspectRatio: Double($0 % 4 + 1) / 2) }
        let before = MasonryLayout.columns(for: Array(photos.prefix(8)))
        let after = MasonryLayout.columns(for: photos)
        for (old, new) in zip(before, after) {
            #expect(Array(new.prefix(old.count)).map(\.id) == old.map(\.id))
        }
    }
}
