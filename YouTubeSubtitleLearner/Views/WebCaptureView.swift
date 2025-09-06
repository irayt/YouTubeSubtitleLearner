import SwiftUI
import WebKit

struct WebCaptureView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var urlString: String
    @State private var isCapturing = false
    @State private var status = ""
    @State private var web: WKWebView = WKWebView()
    private let localeId: String
    @State private var autoStarted = false
    @State private var captureSeconds = 30
    @State private var elapsed = 0
    @State private var stopTask: Task<Void, Never>? = nil

    init(initialURL: String, localeId: String) {
        _urlString = State(initialValue: initialURL)
        self.localeId = localeId
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("URL").font(.caption).foregroundColor(.secondary)
                TextField("https://…", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                HStack { if isCapturing { Text("解析中… (\(elapsed)/\(captureSeconds)s)").foregroundColor(.red) } ; Spacer() ; Button("再読み込み") { load() }.disabled(!isCapturing) }
            }
            .padding(8)
            WebViewContainer(webView: web)
            HStack {
                Text(status).font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("閉じる") { presentationMode.wrappedValue.dismiss() }
            }.padding(8)
        }
        .onAppear {
            setupWeb()
            Task { await autoStartIfNeeded() }
        }
    }

    private func setupWeb() {
        web.allowsBackForwardNavigationGestures = true
        web.configuration.allowsInlineMediaPlayback = true
        #if os(iOS)
        web.configuration.mediaTypesRequiringUserActionForPlayback = []
        #endif
        load()
    }

    private func load() { if let u = URL(string: urlString) { web.load(URLRequest(url: u)) } }

    private func toggleCapture() async { /* no-op: 自動開始・自動停止 */ }

    private func autoStartIfNeeded() async {
        guard !autoStarted, !isCapturing else { return }
        do {
            try WebCaptureShared.shared.start()
            isCapturing = true
            autoStarted = true
            status = "録音中。自動で解析します"
            startAutoStopTimer()
        } catch {
            status = "録音開始に失敗: \(error.localizedDescription)"
        }
    }

    private func startAutoStopTimer() {
        stopTask?.cancel()
        elapsed = 0
        stopTask = Task { @MainActor in
            while !Task.isCancelled, elapsed < captureSeconds {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                elapsed += 1
            }
            if !Task.isCancelled { await stopAndAnalyze() }
        }
    }

    private func stopAndAnalyze() async {
        status = "保存中..."
        do {
            let url = try await WebCaptureShared.shared.stop()
            status = "文字起こし中..."
            let (words, subs) = try await TranscriptionService.transcribe(audioURL: url, localeId: localeId)
            // Build project using remoteURL for streaming
            var prj = AnalysisProject(
                id: UUID(),
                title: (URL(string: urlString)?.host ?? "WebCapture"),
                createdAt: Date(),
                localeId: localeId,
                videoFile: nil,
                audioFile: nil,
                subtitlesFile: "subtitles.json",
                wordsFile: "words.json",
                remoteURL: urlString
            )
            let folder = ProjectStore.shared.folder(for: prj)
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
            try enc.encode(subs).write(to: folder.appendingPathComponent(prj.subtitlesFile), options: .atomic)
            try enc.encode(words).write(to: folder.appendingPathComponent(prj.wordsFile), options: .atomic)
            ProjectStore.shared.upsert(project: prj)
            status = "完了"
            presentationMode.wrappedValue.dismiss()
        } catch { status = "失敗: \(error.localizedDescription)" }
        isCapturing = false
        stopTask?.cancel(); stopTask = nil
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// Keep a shared AudioCapture to preserve writer across start/stop from the view
final class WebCaptureShared {
    static let shared = WebCaptureShared()
    private let svc = AudioCaptureService()
    func start() throws { try svc.start() }
    func stop() async throws -> URL { try await svc.stop() }
}
