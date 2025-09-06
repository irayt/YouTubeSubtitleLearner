import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ProjectsView()
                .tabItem { Label("ホーム", systemImage: "house") }
            VideoPlayerView()
                .tabItem { Label("プレイヤー", systemImage: "play.rectangle") }
            WordbookView()
                .tabItem { Label("単語帳", systemImage: "book") }
            ProfileView()
                .tabItem { Label("プロフィール", systemImage: "person") }
        }
    }
}

#Preview {
    ContentView()
}
