import SwiftUI

struct RootTabView: View {
    @State private var importMessage: String? = nil
    @State private var showImportAlert = false

    var body: some View {
        TabView {
            WordListView(favoritesOnly: false)
                .tabItem { Label("전체", systemImage: "list.bullet") }

            WordListView(favoritesOnly: true)
                .tabItem { Label("즐겨찾기", systemImage: "star.fill") }

            SearchView()
                .tabItem { Label("검색", systemImage: "magnifyingglass") }

            GameView()
                .tabItem { Label("게임", systemImage: "gamecontroller") }

            SettingsView()
                .tabItem { Label("설정", systemImage: "gear") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vocabImported)) { note in
            if let msg = note.object as? String {
                importMessage = msg
                showImportAlert = true
            }
        }
        .alert("불러오기 완료", isPresented: $showImportAlert) {
            Button("확인") {}
        } message: {
            Text(importMessage ?? "")
        }
    }
}
