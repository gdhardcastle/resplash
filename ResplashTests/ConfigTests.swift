import Testing
@testable import Resplash

struct ConfigTests {
    @Test(arguments: [nil, "", "  ", "YOUR_UNSPLASH_ACCESS_KEY", "$(UNSPLASH_ACCESS_KEY)"])
    func invalidKeyThrows(key: String?) {
        let info: [String: Any] = key.map { [Config.accessKeyInfoPlistKey: $0] } ?? [:]
        #expect(throws: Config.Error.missingAccessKey) {
            try Config(infoDictionary: info)
        }
    }

    @Test func validKeyIsTrimmed() throws {
        let config = try Config(infoDictionary: [Config.accessKeyInfoPlistKey: " abc123\n"])
        #expect(config.unsplashAccessKey == "abc123")
    }
}
