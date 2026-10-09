import CryptoKit
import Foundation

/// The encoded bytes as downloaded, one file per URL, so a relaunch or a memory eviction costs a file
/// read instead of a download. Keyed by URL alone: the same bytes serve every decoded size.
/// Least recently used files are deleted once the total passes the limit.
actor DiskImageCache {

    private let directory: URL
    private let byteLimit: Int
    /// Counted lazily on first use, then kept up to date as files are written and deleted.
    private var totalBytes: Int?

    init(directory: URL, byteLimit: Int = 200_000_000) {
        self.directory = directory
        self.byteLimit = byteLimit
    }

    func data(for url: URL) -> Data? {
        let file = fileURL(for: url)
        guard let data = try? Data(contentsOf: file) else { return nil }
        // Reading counts as use, so eviction order is by recency, not by when the file was written.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return data
    }

    func store(_ data: Data, for url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? data.write(to: fileURL(for: url), options: .atomic)) != nil else { return }
        totalBytes = currentTotal() + data.count
        if currentTotal() > byteLimit { evict() }
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: fileURL(for: url))
        totalBytes = nil
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return directory.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
    }

    private func currentTotal() -> Int {
        if let totalBytes { return totalBytes }
        let total = files().reduce(0) { $0 + $1.size }
        totalBytes = total
        return total
    }

    /// Deletes the oldest files until the cache is down to 80% of its limit, so it doesn't evict on every write.
    private func evict() {
        var remaining = currentTotal()
        for file in files().sorted(by: { $0.modified < $1.modified }) where remaining > byteLimit * 8 / 10 {
            try? FileManager.default.removeItem(at: file.url)
            remaining -= file.size
        }
        totalBytes = remaining
    }

    private func files() -> [(url: URL, size: Int, modified: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
            return (url, size, modified)
        }
    }
}
