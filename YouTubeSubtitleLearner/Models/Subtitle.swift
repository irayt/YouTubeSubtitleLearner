import Foundation

struct Subtitle: Codable, Identifiable {
    let id = UUID()
    let start: Double
    let duration: Double
    let text: String
    
    var endTime: Double {
        return start + duration
    }
    
    private enum CodingKeys: String, CodingKey {
        case start, duration, text
    }
}
