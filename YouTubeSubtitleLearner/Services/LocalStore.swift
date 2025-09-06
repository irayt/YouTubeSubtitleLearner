import Foundation

enum LocalStore {
    private static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var subtitlesURL: URL { docs.appendingPathComponent("subtitles.json") }
    private static var wordsURL: URL { docs.appendingPathComponent("words.json") }

    static func save(subtitles: [Subtitle], words: [WordToken]) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        let sdata = try enc.encode(subtitles)
        let wdata = try enc.encode(words)
        try sdata.write(to: subtitlesURL, options: .atomic)
        try wdata.write(to: wordsURL, options: .atomic)
    }

    static func load() -> (subtitles: [Subtitle], words: [WordToken])? {
        let dec = JSONDecoder()
        guard FileManager.default.fileExists(atPath: subtitlesURL.path) else { return nil }
        do {
            let sdata = try Data(contentsOf: subtitlesURL)
            let wdata = try Data(contentsOf: wordsURL)
            let subs = try dec.decode([Subtitle].self, from: sdata)
            let words = try dec.decode([WordToken].self, from: wdata)
            return (subs, words)
        } catch {
            return nil
        }
    }
}

