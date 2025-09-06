import SwiftUI

struct ProjectsView: View {
    @State private var projects: [AnalysisProject] = ProjectStore.shared.list()
    @State private var showVideoPicker = false
    @State private var remoteURL = ""
    @AppStorage("pref_locale") private var localeId: String = Locale.current.identifier
    @State private var isBusy = false
    @State private var status = ""
    @State private var fraction: Double? = nil
    @State private var openProject: AnalysisProject?
    @AppStorage("pref_allow_network") private var allowNetwork = false
    @State private var showWebCapture = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                // URL
                VStack(alignment: .leading, spacing: 6) {
                    Text("動画URL").font(.caption).foregroundColor(.secondary)
                    TextField("https://…", text: $remoteURL)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal)

                // Locale
                VStack(alignment: .leading, spacing: 6) {
                    Text("ロケール").font(.caption).foregroundColor(.secondary)
                    Menu {
                        ForEach(commonLocales, id: \.self) { loc in
                            Button(action: { localeId = loc }) { Text(loc) }
                        }
                        Button("端末の言語") { localeId = Locale.current.identifier }
                    } label: {
                        HStack { Text(localeId).lineLimit(1); Spacer(); Image(systemName: "chevron.down") }
                            .padding(10)
                            .background(Color.gray.opacity(0.12))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)

                // Network toggle
                Toggle(isOn: $allowNetwork) { Text("ネットワーク許可") }
                    .padding(.horizontal)

                // Actions
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        if URLMediaType.isDirectVideo(remoteURL) { Task { await analyzeRemote() } }
                        else { showWebCapture = true }
                    } label: { Text("解析").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy || remoteURL.isEmpty || !allowNetwork)

                    Button { showVideoPicker = true } label: { Text("ローカル動画を選択…").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                }
                .padding(.horizontal)

                // Progress
                if isBusy {
                    VStack(alignment: .leading, spacing: 6) {
                        if let f = fraction { ProgressView(value: f) }
                        Text(status).font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }

                // Projects list
                List {
                    ForEach(projects) { p in
                        Button(action: { openProject = p }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.headline)
                                Text(metaLine(for: p)).font(.caption).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button(role: .destructive) { delete(p) } label: { Label("削除", systemImage: "trash") } }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("解析プロジェクト")
            .fileImporter(isPresented: $showVideoPicker, allowedContentTypes: [.movie]) { res in
                switch res {
                case .success(let url): Task { await analyzeLocal(url) }
                case .failure: status = "読み込み失敗"
                }
            }
            .sheet(item: $openProject) { p in
                VideoPlayerView(project: p)
            }
            .sheet(isPresented: $showWebCapture) {
                WebCaptureView(initialURL: remoteURL, localeId: localeId)
            }
        }
    }

    private func reload() { projects = ProjectStore.shared.list() }
    private func delete(_ p: AnalysisProject) { ProjectStore.shared.delete(project: p); reload() }
    private var commonLocales: [String] { ["ja-JP","en-US","ko-KR","zh-CN","fr-FR","de-DE","es-ES"] }
    private func metaLine(for p: AnalysisProject) -> String {
        let folder = ProjectStore.shared.folder(for: p)
        let v = p.videoFile.flatMap { ProjectStore.shared.fileURL(for: p, relative: $0) }
        let a = p.audioFile.flatMap { ProjectStore.shared.fileURL(for: p, relative: $0) }
        let vs = v.flatMap { fileSizeString($0) } ?? (p.remoteURL != nil ? "stream" : "-")
        let asz = a.flatMap { fileSizeString($0) } ?? "-"
        return "\(p.createdAt.formatted(date: .abbreviated, time: .shortened))  |  \(p.localeId ?? Locale.current.identifier)  |  Video: \(vs)  Audio: \(asz)"
    }

    private func analyzeRemote() async {
        isBusy = true; status = "ダウンロード中..."; fraction = 0
        do {
            guard let url = URL(string: remoteURL) else { status = "URLが不正"; isBusy = false; return }
            let p = try await AnalysisPipeline.shared.analyze(remoteURL: url, localeId: localeId) { prog in status = prog.message; fraction = prog.fraction }
            reload(); openProject = p
        } catch { status = error.localizedDescription }
        isBusy = false; fraction = nil
    }

    private func analyzeLocal(_ url: URL) async {
        isBusy = true; status = "コピー中..."; fraction = 0
        do {
            let p = try await AnalysisPipeline.shared.analyzeLocal(videoURL: url, localeId: localeId) { prog in status = prog.message; fraction = prog.fraction }
            reload(); openProject = p
        } catch { status = error.localizedDescription }
        isBusy = false; fraction = nil
    }
}
