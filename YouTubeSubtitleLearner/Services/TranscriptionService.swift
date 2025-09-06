import Foundation
import Speech
import AVFoundation

enum TranscriptionError: Error { case notAuthorized, recognizerUnavailable, failed }

enum TranscriptionService {
    typealias Progress = (Double) -> Void  // 0.0 ... 1.0
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
        }
    }

    static func transcribe(audioURL: URL, localeId: String?, progress: Progress? = nil) async throws -> (words: [WordToken], subtitles: [Subtitle]) {
        let status = await requestAuthorization()
        guard status == .authorized else { throw TranscriptionError.notAuthorized }
        let locale = localeId.flatMap { Locale(identifier: $0) } ?? Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        // Chunked transcription for long audio
        let asset = AVURLAsset(url: audioURL)
        let total = CMTimeGetSeconds(asset.duration)
        let maxChunk: Double = 55.0
        let overlap: Double = 0.3
        if total <= maxChunk + 1 {
            let (w, s) = try await transcribeOne(recognizer: recognizer, audioURL: audioURL)
            progress?(1.0)
            return (w, s)
        }
        var offset: Double = 0
        var wordsAll: [WordToken] = []
        var chunks: [(start: Double, dur: Double)] = []
        while offset < total {
            let dur = min(maxChunk, total - offset)
            chunks.append((offset, dur))
            offset += (maxChunk - overlap)
        }
        for (i, c) in chunks.enumerated() {
            let clip = try await exportClip(url: audioURL, start: c.start, duration: c.dur)
            let (w, _) = try await transcribeOne(recognizer: recognizer, audioURL: clip, baseOffset: c.start)
            wordsAll.append(contentsOf: w)
            progress?(Double(i + 1) / Double(chunks.count))
            try? FileManager.default.removeItem(at: clip)
        }
        let subtitles = buildSubtitles(from: wordsAll)
        return (wordsAll, subtitles)
    }

    private static func exportClip(url: URL, start: Double, duration: Double) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.failed
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        export.outputURL = out
        export.outputFileType = .m4a
        let s = CMTime(seconds: start, preferredTimescale: 600)
        let d = CMTime(seconds: duration, preferredTimescale: 600)
        export.timeRange = CMTimeRange(start: s, duration: d)
        return try await withCheckedThrowingContinuation { cont in
            export.exportAsynchronously {
                if export.status == .completed { cont.resume(returning: out) }
                else { cont.resume(throwing: TranscriptionError.failed) }
            }
        }
    }

    private static func transcribeOne(recognizer: SFSpeechRecognizer, audioURL: URL, baseOffset: Double = 0) async throws -> (words: [WordToken], subtitles: [Subtitle]) {
        let req = SFSpeechURLRecognitionRequest(url: audioURL)
        if #available(iOS 13.0, *) { req.requiresOnDeviceRecognition = true }
        req.shouldReportPartialResults = false
        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: req) { result, error in
                if let error { cont.resume(throwing: error); return }
                guard let result, result.isFinal else { return }
                cont.resume(returning: result)
            }
        }
        let segments = result.bestTranscription.segments
        let words: [WordToken] = segments.map { seg in
            let start = baseOffset + seg.timestamp
            return WordToken(start: start, duration: seg.duration, text: seg.substring, sentIndex: nil, wordIndex: seg.substringRange.location)
        }
        let subtitles = buildSubtitles(from: words)
        return (words, subtitles)
    }
    private static func buildSubtitles(from words: [WordToken]) -> [Subtitle] {
        guard !words.isEmpty else { return [] }
        let maxWindow: Double = 4.0
        var out: [Subtitle] = []
        var buf: [WordToken] = []
        var windowStart = words.first!.start
        for w in words {
            if buf.isEmpty { windowStart = w.start }
            buf.append(w)
            let windowDur = (w.start + w.duration) - windowStart
            if windowDur >= maxWindow || w.text.last.map({ ".!?".contains($0) }) == true {
                let text = buf.map { $0.text }.joined(separator: " ")
                let end = buf.last!.start + buf.last!.duration
                out.append(Subtitle(start: windowStart, duration: max(0, end - windowStart), text: text))
                buf.removeAll(keepingCapacity: true)
            }
        }
        if !buf.isEmpty {
            let text = buf.map { $0.text }.joined(separator: " ")
            let end = buf.last!.start + buf.last!.duration
            out.append(Subtitle(start: windowStart, duration: max(0, end - windowStart), text: text))
        }
        return out
    }
}
