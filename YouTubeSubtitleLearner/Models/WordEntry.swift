import Foundation

struct WordEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var meaning: String?
    var createdAt: Date
    var isKnown: Bool
}

