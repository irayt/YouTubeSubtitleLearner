import Foundation

enum YouTubeIDParser {
    static func extractID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // Already ID-like and not a URL
        let idRegex = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_-]{6,}$")
        if idRegex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)) != nil,
           !trimmed.contains("http") {
            return trimmed
        }

        func toURL(_ s: String) -> URL? {
            if let u = URL(string: s) { return u }
            return URL(string: "https://" + s)
        }
        guard let url = toURL(trimmed) else { return nil }
        let host = (url.host ?? "").lowercased()
        let comps = url.pathComponents.filter { $0 != "/" }

        if host.contains("youtu.be") {
            return comps.first
        }
        if host.contains("youtube.com") {
            if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
                if let id = items.first(where: { $0.name.lowercased() == "v" })?.value, !id.isEmpty { return id }
            }
            if comps.count >= 2 {
                let first = comps[0].lowercased()
                let id = comps[1]
                if ["shorts","live","embed","v"].contains(first) { return id }
            }
        }
        return nil
    }
}
