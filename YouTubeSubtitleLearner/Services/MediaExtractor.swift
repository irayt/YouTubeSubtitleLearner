import Foundation
import AVFoundation

enum MediaExtractorError: Error { case exportFailed }

enum MediaExtractor {
    private static var audiosDir: URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = root.appendingPathComponent("Audios", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func extractM4A(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaExtractorError.exportFailed
        }
        let out = audiosDir.appendingPathComponent(UUID().uuidString + ".m4a")
        export.outputURL = out
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        return try await withCheckedThrowingContinuation { cont in
            export.exportAsynchronously {
                if export.status == .completed { cont.resume(returning: out) }
                else { cont.resume(throwing: MediaExtractorError.exportFailed) }
            }
        }
    }
}

