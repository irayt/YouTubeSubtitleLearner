import Foundation

struct AnalysisProject: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var localeId: String?
    // Relative paths under project dir
    var videoFile: String?
    var audioFile: String?
    var subtitlesFile: String
    var wordsFile: String
    // Remote streaming source (e.g., YouTube direct file URL after analysis)
    var remoteURL: String?

    // Derived
    var folderName: String { id.uuidString }
}
