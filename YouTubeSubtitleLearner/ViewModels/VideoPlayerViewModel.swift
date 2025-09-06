import Foundation
import AVFoundation
import Combine

@MainActor
class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var subtitles: [Subtitle] = []
    @Published var wordTokens: [WordToken] = []
    @Published var currentSubtitle: Subtitle?
    @Published var currentWordIndex: Int?
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying = false
    
    // 自動取得用のUI状態
    @Published var statusText: String = ""
    @Published var isBusy: Bool = false
    
    private var timeObserver: Any?
    
    init() {
        Task { @MainActor in
            // 初期はドキュメント保存分を優先。なければバンドルのローカル字幕＆サンプル動画
            if let loaded = LocalStore.load() {
                self.subtitles = loaded.subtitles
                self.wordTokens = loaded.words
            } else {
                loadSubtitles()
            }
            loadVideo()
        }
    }
    
    deinit {
        Task { @MainActor in
            if let timeObserver = timeObserver {
                player?.removeTimeObserver(timeObserver)
            }
        }
    }
    
    private func loadVideo() {
        if let cached = VideoCache.cachedVideoURL() {
            player = AVPlayer(url: cached)
        } else {
            // オフライン原則のため、サンプルのオンライン動画は使わない
            player = nil
        }
        setupTimeObserver()
    }
    
    private func loadSubtitles() {
        guard let url = Bundle.main.url(forResource: "subtitles", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("Could not load subtitles.json")
            return
        }
        
        do {
            subtitles = try JSONDecoder().decode([Subtitle].self, from: data)
            // Derive approximate word tokens for local sample
            self.wordTokens = subtitles.reduce(into: [WordToken]()) { acc, sub in
                let tokens = sub.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                guard !tokens.isEmpty else { return }
                let step = sub.duration / Double(tokens.count)
                for (i, w) in tokens.enumerated() {
                    acc.append(WordToken(start: sub.start + step * Double(i), duration: max(0, step), text: w, sentIndex: nil, wordIndex: i))
                }
            }
            try? LocalStore.save(subtitles: self.subtitles, words: self.wordTokens)
        } catch {
            print("Error decoding subtitles: \(error)")
        }
    }
    
    func setupTimeObserver() {
        guard let player = player else { return }
        
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 1000),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
                self?.updateCurrentSubtitle()
            }
        }
    }
    
    private func updateCurrentSubtitle() {
        currentSubtitle = subtitles.first { subtitle in
            currentTime >= subtitle.start && currentTime <= subtitle.endTime
        }
        updateCurrentWord()
    }
    
    func play() {
        player?.play()
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func seek(to time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 1000))
    }

    // MARK: - Local only (no Supabase)
    func startLoad() async {
        // 何もしない（ローカル運用）。必要であればインポートを案内
        statusText = "オフライン運用: 右の[インポート]から字幕を読み込み"
    }

    // Import helpers
    func setImported(subs: [Subtitle], words: [WordToken]) {
        self.subtitles = subs
        self.wordTokens = words
        try? LocalStore.save(subtitles: subs, words: words)
        self.statusText = "ローカルに保存しました"
    }

    // MARK: - Full offline pipeline: download → extract audio → transcribe → save
    func analyzeRemoteVideo(from urlString: String, localeId: String? = nil) async {
        guard let url = URL(string: urlString) else { statusText = "URLが不正です"; return }
        await analyzeVideo(at: url, isRemote: true, localeId: localeId)
    }

    func analyzeLocalVideo(at url: URL, localeId: String? = nil) async {
        await analyzeVideo(at: url, isRemote: false, localeId: localeId)
    }

    private func analyzeVideo(at url: URL, isRemote: Bool, localeId: String?) async {
        isBusy = true
        statusText = isRemote ? "ダウンロード中..." : "コピー中..."
        do {
            let videoURL: URL
            if isRemote {
                videoURL = try await VideoCache.download(from: url)
            } else {
                videoURL = try VideoCache.saveLocalCopy(of: url)
            }
            await MainActor.run { self.player = AVPlayer(url: videoURL); self.setupTimeObserver() }
            statusText = "音声抽出中..."
            let audioURL = try await MediaExtractor.extractM4A(from: videoURL)
            statusText = "文字起こし中...（オンデバイス）"
            let (words, subs) = try await TranscriptionService.transcribe(audioURL: audioURL, localeId: localeId)
            await MainActor.run {
                self.subtitles = subs
                self.wordTokens = words
                try? LocalStore.save(subtitles: subs, words: words)
                self.statusText = "解析完了"
            }
        } catch {
            await MainActor.run { self.statusText = "解析失敗: \(error.localizedDescription)" }
        }
        await MainActor.run { self.isBusy = false }
    }

    private func updateCurrentWord() {
        guard !wordTokens.isEmpty else { self.currentWordIndex = nil; return }
        if let idx = wordTokens.firstIndex(where: { currentTime >= $0.start && currentTime <= $0.endTime }) {
            self.currentWordIndex = idx
        } else {
            // If no exact match, pick the latest word before current time
            if let idx = wordTokens.lastIndex(where: { $0.start <= currentTime }) {
                self.currentWordIndex = idx
            } else {
                self.currentWordIndex = nil
            }
        }
    }
}
