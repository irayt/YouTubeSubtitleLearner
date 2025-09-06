import Foundation

enum VideoCacheError: Error { case invalidURL, downloadFailed }

enum VideoCache {
    private static var videosDir: URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = root.appendingPathComponent("Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cachedVideoURL() -> URL? {
        // Use the most recent video in Videos dir
        guard let files = try? FileManager.default.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        return files.sorted { (a, b) in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }.first
    }

    static func saveLocalCopy(of url: URL) throws -> URL {
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let dest = videosDir.appendingPathComponent(UUID().uuidString + "." + ext)
        if url.isFileURL {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } else {
            throw VideoCacheError.invalidURL
        }
    }

    static func download(from remote: URL) async throws -> URL {
        let (tmpURL, response) = try await URLSession.shared.download(from: remote)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VideoCacheError.downloadFailed
        }
        let ext = remote.pathExtension.isEmpty ? "mp4" : remote.pathExtension
        let dest = videosDir.appendingPathComponent(UUID().uuidString + "." + ext)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmpURL, to: dest)
        return dest
    }
}

