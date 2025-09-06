import Foundation

struct WordToken: Codable, Identifiable {
    let id = UUID()
    let start: Double
    let duration: Double
    let text: String
    let sentIndex: Int?
    let wordIndex: Int?

    var endTime: Double { start + duration }

    private enum CodingKeys: String, CodingKey {
        case start, duration, text
        case sentIndex = "sent_index"
        case wordIndex = "word_index"
    }
}

