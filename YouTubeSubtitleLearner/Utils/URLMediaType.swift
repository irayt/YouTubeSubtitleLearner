import Foundation

enum URLMediaType {
    static let directVideoExts: Set<String> = ["mp4","mov","m4v","m3u8","ts","webm"]

    static func isDirectVideo(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        let ext = url.pathExtension.lowercased()
        if directVideoExts.contains(ext) { return true }
        return false
    }
}

