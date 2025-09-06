import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct VideoPlayerView: View {
    var project: AnalysisProject? = nil
    @StateObject private var viewModel = VideoPlayerViewModel()
    @AppStorage("pref_auto_scroll") private var autoScroll = true
    @State private var showingImporter = false
    @State private var showingVideoPicker = false
    @State private var videoURLInput: String = ""
    // 言語ロケール（空で自動判定）。例: "ja-JP", "en-US"
    @AppStorage("pref_locale") private var preferredLocale: String = Locale.current.identifier
    
    var body: some View {
        VStack(spacing: 0) {
            // Video Player
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .frame(height: 250)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 250)
                    .overlay(
                        Text("Loading Video...")
                            .foregroundColor(.white)
                    )
            }
            
            // Local-only controls (import + status)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button("インポート(VTT/SRT/JSON)") { showingImporter = true }
                        .buttonStyle(.bordered)
                    Button("保存") {
                        try? LocalStore.save(subtitles: viewModel.subtitles, words: viewModel.wordTokens)
                        viewModel.statusText = "保存しました"
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Text(viewModel.statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    TextField("動画URL (mp4等)", text: $videoURLInput)
                        .textFieldStyle(.roundedBorder)
                    Button("解析") {
                        Task { await viewModel.analyzeRemoteVideo(from: videoURLInput, localeId: preferredLocale) }
                    }
                    .disabled(viewModel.isBusy || videoURLInput.isEmpty)
                    Button("ローカル動画…") { showingVideoPicker = true }
                        .disabled(viewModel.isBusy)
                }
            }
            .padding()
            
            // Controls
            HStack {
                Button(viewModel.isPlaying ? "Pause" : "Play") {
                    if viewModel.isPlaying {
                        viewModel.pause()
                    } else {
                        viewModel.play()
                    }
                }
                .padding()
                
                Spacer()
                
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
                    .padding(.trailing, 8)

                Text("Time: \(String(format: "%.1f", viewModel.currentTime))s")
                    .font(.caption)
                    .padding()
            }
            
            // Word-level view and auto-scroll
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(viewModel.wordTokens.enumerated()), id: \.offset) { idx, tok in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(timeString(from: tok.start))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                                Text(tok.text)
                                    .fontWeight(viewModel.currentWordIndex == idx ? .bold : .regular)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(viewModel.currentWordIndex == idx ? Color.yellow.opacity(0.35) : Color.gray.opacity(0.08))
                                    .cornerRadius(6)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.seek(to: tok.start) }
                            .id(idx)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: viewModel.currentWordIndex) { newIdx in
                    guard autoScroll, let i = newIdx else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(i, anchor: .center)
                        }
                    }
                }
                .onChange(of: viewModel.wordTokens.count) { _ in
                    guard autoScroll else { return }
                    if let i = viewModel.currentWordIndex ?? viewModel.wordTokens.indices.first {
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                proxy.scrollTo(i, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [UTType(filenameExtension: "vtt")!, UTType(filenameExtension: "srt")!, .json]) { result in
            switch result {
            case .success(let url):
                importSubtitles(from: url)
            case .failure:
                viewModel.statusText = "インポート失敗"
            }
        }
        .fileImporter(isPresented: $showingVideoPicker, allowedContentTypes: [.movie]) { result in
            switch result {
            case .success(let url):
                Task { await viewModel.analyzeLocalVideo(at: url, localeId: preferredLocale) }
            case .failure:
                viewModel.statusText = "動画の読み込みに失敗しました"
            }
        }
        .onAppear { loadProjectIfNeeded() }
    }
}

private func timeString(from seconds: TimeInterval) -> String {
    let minutes = Int(seconds) / 60
    let seconds = Int(seconds) % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

// MARK: - Import helpers
extension VideoPlayerView {
    fileprivate func importSubtitles(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let subs = SubtitlesParser.parse(data: data, fileExtension: url.pathExtension)
            guard !subs.isEmpty else {
                viewModel.statusText = "解析できませんでした"
                return
            }
            // Derive word tokens by even split per cue as an approximation
            let words: [WordToken] = subs.reduce(into: [WordToken]()) { acc, sub in
                let tokens = sub.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                guard !tokens.isEmpty else { return }
                let step = sub.duration / Double(tokens.count)
                for (i, w) in tokens.enumerated() {
                    acc.append(WordToken(start: sub.start + step * Double(i), duration: max(0, step), text: w, sentIndex: nil, wordIndex: i))
                }
            }
            viewModel.setImported(subs: subs, words: words)
        } catch {
            viewModel.statusText = "読み込みエラー: \(error.localizedDescription)"
        }
    }

    @MainActor
    fileprivate func loadProjectIfNeeded() {
        guard let p = project else { return }
        // load media and texts from project store
        let folder = ProjectStore.shared.folder(for: p)
        if let remote = p.remoteURL, let url = URL(string: remote) {
            viewModel.player = AVPlayer(url: url)
        } else if let vf = p.videoFile {
            let videoURL = ProjectStore.shared.fileURL(for: p, relative: vf)
            viewModel.player = AVPlayer(url: videoURL)
        }
        viewModel.setupTimeObserver()
        if let sdata = try? Data(contentsOf: folder.appendingPathComponent(p.subtitlesFile)),
           let wdata = try? Data(contentsOf: folder.appendingPathComponent(p.wordsFile)) {
            let dec = JSONDecoder()
            if let subs = try? dec.decode([Subtitle].self, from: sdata),
               let words = try? dec.decode([WordToken].self, from: wdata) {
                viewModel.setImported(subs: subs, words: words)
            }
        }
    }
}

struct SubtitleRowView: View {
    let subtitle: Subtitle
    let isActive: Bool
    let onSubtitleTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(timeString(from: subtitle.start))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            Text(subtitle.text)
                .fontWeight(isActive ? .bold : .regular)
                .padding()
                .background(isActive ? Color.yellow.opacity(0.3) : Color.gray.opacity(0.1))
                .cornerRadius(8)
                .onTapGesture {
                    onSubtitleTap()
                }
        }
    }
    
    private func timeString(from seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
