import Foundation

final class WordbookStore: ObservableObject {
    static let shared = WordbookStore()
    @Published private(set) var items: [WordEntry] = []
    private init() { load() }

    private var dir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Wordbook", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private var fileURL: URL { dir.appendingPathComponent("wordbook.json") }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { items = []; return }
        items = (try? JSONDecoder().decode([WordEntry].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
        if let d = try? enc.encode(items) { try? d.write(to: fileURL, options: .atomic) }
    }

    func add(text: String, meaning: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let e = WordEntry(id: UUID(), text: trimmed, meaning: (meaning?.isEmpty == true ? nil : meaning), createdAt: Date(), isKnown: false)
        items.insert(e, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) { items.remove(atOffsets: offsets); save() }
    func toggleKnown(_ entry: WordEntry) { if let i = items.firstIndex(of: entry) { items[i].isKnown.toggle(); save() } }
    func importTokens(_ tokens: [WordToken]) {
        let existing = Set(items.map { $0.text.lowercased() })
        var added = false
        for t in tokens {
            let w = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !w.isEmpty, !existing.contains(w.lowercased()) else { continue }
            items.insert(WordEntry(id: UUID(), text: w, meaning: nil, createdAt: Date(), isKnown: false), at: 0)
            added = true
        }
        if added { save() }
    }
}

