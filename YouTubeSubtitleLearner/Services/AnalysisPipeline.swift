import Foundation

struct AnalysisProgress {
    enum Stage: String { case downloading, copying, extractingAudio, transcribing, saving, done }
    let stage: Stage
    let message: String
    let fraction: Double? // 0.0 ... 1.0
}

final class AnalysisPipeline {
    typealias ProgressHandler = (AnalysisProgress) -> Void

    static let shared = AnalysisPipeline()

    private init() {}

    func analyze(remoteURL: URL, localeId: String?, progress: ProgressHandler? = nil) async throws -> AnalysisProject {
        progress?(AnalysisProgress(stage: .downloading, message: "ダウンロード中", fraction: 0))
        let video = try await VideoCache.download(from: remoteURL)
        return try await analyzeLocal(videoURL: video, localeId: localeId, isRemote: true, remoteSource: remoteURL, initialStage: .extractingAudio, progress: progress)
    }

    func analyzeLocal(videoURL: URL, localeId: String?, progress: ProgressHandler? = nil) async throws -> AnalysisProject {
        return try await analyzeLocal(videoURL: videoURL, localeId: localeId, isRemote: false, remoteSource: nil, initialStage: .copying, progress: progress)
    }

    private func analyzeLocal(videoURL: URL, localeId: String?, isRemote: Bool, remoteSource: URL?, initialStage: AnalysisProgress.Stage, progress: ProgressHandler?) async throws -> AnalysisProject {
        progress?(AnalysisProgress(stage: initialStage, message: initialStage == .copying ? "コピー中" : "", fraction: 0))
        // Remote: already downloaded into app space; Local: copy into cache
        let workingVideo = isRemote ? videoURL : try VideoCache.saveLocalCopy(of: videoURL)

        progress?(AnalysisProgress(stage: .extractingAudio, message: "音声抽出中", fraction: 0))
        let audio = try await MediaExtractor.extractM4A(from: workingVideo)

        progress?(AnalysisProgress(stage: .transcribing, message: "文字起こし中", fraction: 0))
        let (words, subs) = try await TranscriptionService.transcribe(audioURL: audio, localeId: localeId) { frac in
            progress?(AnalysisProgress(stage: .transcribing, message: "文字起こし中", fraction: frac))
        }

        progress?(AnalysisProgress(stage: .saving, message: "保存中", fraction: 0))
        let id = UUID()
        var project = AnalysisProject(
            id: id,
            title: workingVideo.deletingPathExtension().lastPathComponent,
            createdAt: Date(),
            localeId: localeId,
            videoFile: isRemote ? nil : ("video." + (workingVideo.pathExtension.isEmpty ? "mp4" : workingVideo.pathExtension)),
            audioFile: isRemote ? nil : "audio.m4a",
            subtitlesFile: "subtitles.json",
            wordsFile: "words.json",
            remoteURL: isRemote ? remoteSource?.absoluteString : nil
        )
        let folder = ProjectStore.shared.folder(for: project)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
        try enc.encode(subs).write(to: folder.appendingPathComponent(project.subtitlesFile), options: .atomic)
        try enc.encode(words).write(to: folder.appendingPathComponent(project.wordsFile), options: .atomic)
        // Media handling
        if isRemote {
            // Delete temporary working files after analysis (no caching of YouTube media)
            try? FileManager.default.removeItem(at: workingVideo)
            try? FileManager.default.removeItem(at: audio)
        } else {
            // Move media into the project folder for local sources
            let destVideo = folder.appendingPathComponent(project.videoFile ?? "video.mp4")
            let destAudio = folder.appendingPathComponent(project.audioFile ?? "audio.m4a")
            try? FileManager.default.removeItem(at: destVideo)
            try? FileManager.default.removeItem(at: destAudio)
            try? FileManager.default.moveItem(at: workingVideo, to: destVideo)
            try? FileManager.default.moveItem(at: audio, to: destAudio)
        }
        ProjectStore.shared.upsert(project: project)

        progress?(AnalysisProgress(stage: .done, message: "完了", fraction: 1))
        return project
    }
}
