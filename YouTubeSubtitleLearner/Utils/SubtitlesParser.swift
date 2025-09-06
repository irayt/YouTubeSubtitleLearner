import Foundation

enum SubtitlesParser {
    struct Cue { let start: Double; let end: Double; let text: String }

    static func parse(data: Data, fileExtension: String) -> [Subtitle] {
        let ext = fileExtension.lowercased()
        if ext == "vtt" { return parseVTT(data: data) }
        if ext == "srt" { return parseSRT(data: data) }
        if ext == "json" { return (try? JSONDecoder().decode([Subtitle].self, from: data)) ?? [] }
        return []
    }

    static func parseVTT(data: Data) -> [Subtitle] {
        guard let raw = String(data: data, encoding: .utf8) else { return [] }
        var cues: [Cue] = []
        var lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // Skip WEBVTT header
        if let first = lines.first, first.uppercased().contains("WEBVTT") { lines.removeFirst() }
        var i = 0
        while i < lines.count {
            // Skip blank and index lines
            if lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }
            if Int(lines[i]) != nil { i += 1 }
            if i >= lines.count { break }
            if let times = parseTimeLine(lines[i]) { // "00:00:01.000 --> 00:00:03.000"
                i += 1
                var textParts: [String] = []
                while i < lines.count, !lines[i].isEmpty { textParts.append(lines[i]); i += 1 }
                let text = textParts.joined(separator: " ")
                cues.append(Cue(start: times.0, end: times.1, text: text))
            } else {
                i += 1
            }
        }
        return cues.map { Subtitle(start: $0.start, duration: max(0, $0.end - $0.start), text: $0.text) }
    }

    static func parseSRT(data: Data) -> [Subtitle] {
        guard let raw = String(data: data, encoding: .utf8) else { return [] }
        let blocks = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        var subs: [Subtitle] = []
        for block in blocks {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count >= 2 else { continue }
            let timeLine = lines[0].contains("-->") ? lines[0] : (lines.dropFirst().first ?? "")
            guard let (start, end) = parseTimeLine(timeLine) else { continue }
            let textLines = lines.drop(while: { Int($0) != nil }).dropFirst() // drop time line
            let text = textLines.joined(separator: " ")
            subs.append(Subtitle(start: start, duration: max(0, end - start), text: text))
        }
        return subs
    }

    private static func parseTimeLine(_ s: String) -> (Double, Double)? {
        // Accept both comma and dot for milliseconds
        let parts = s.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        func toSec(_ t: String) -> Double? {
            let t2 = t.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: ".")
            let comps = t2.components(separatedBy: ":")
            guard comps.count >= 2 else { return nil }
            let h: Double, m: Double, s: Double
            if comps.count == 3 {
                h = Double(comps[0]) ?? 0
                m = Double(comps[1]) ?? 0
                s = Double(comps[2]) ?? 0
            } else {
                h = 0
                m = Double(comps[0]) ?? 0
                s = Double(comps[1]) ?? 0
            }
            return h * 3600 + m * 60 + s
        }
        if let a = toSec(parts[0]), let b = toSec(parts[1]) { return (a, b) }
        return nil
    }
}

