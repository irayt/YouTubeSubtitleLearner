import SwiftUI

struct ProfileView: View {
    @AppStorage("pref_locale") private var prefLocale: String = Locale.current.identifier
    @AppStorage("pref_allow_network") private var allowNetwork: Bool = false
    @AppStorage("pref_auto_scroll") private var autoScroll: Bool = true

    @State private var clearStatus = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("基本設定")) {
                    HStack { Text("既定ロケール"); Spacer(); Text(prefLocale).foregroundColor(.secondary) }
                    Menu("ロケールを選択") {
                        ForEach(locales, id: \.self) { loc in Button(loc) { prefLocale = loc } }
                        Button("端末の言語") { prefLocale = Locale.current.identifier }
                    }
                    Toggle("ネットワーク許可(既定)", isOn: $allowNetwork)
                    Toggle("自動スクロール", isOn: $autoScroll)
                }
                Section(header: Text("ストレージ"), footer: Text(clearStatus)) {
                    Button("キャッシュをクリア") { clearCaches() }
                }
                Section(header: Text("情報")) {
                    Text("アプリは完全オフラインで動作します。オンラインはユーザーが明示的にURL解析を行う場合のみ使用します。").font(.footnote)
                }
            }
            .navigationTitle("プロフィール")
        }
    }

    private let locales = ["ja-JP","en-US","ko-KR","zh-CN","fr-FR","de-DE","es-ES"]

    private func clearCaches() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var removed = 0
        for name in ["Videos","Audios"] {
            let dir = docs.appendingPathComponent(name)
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for f in files { try? fm.removeItem(at: f); removed += 1 }
            }
        }
        clearStatus = "削除: \(removed) 個のファイル"
    }
}

