import SwiftUI

// MARK: - RootTabView (목업 구조 · custom bottom tabbar)

struct RootTabView: View {
    @Environment(\.displayScale) private var displayScale
    @State private var importMessage: String? = nil
    @State private var showImportAlert = false
    @State private var selected: Tab = .all
    @State private var gamePath = NavigationPath()
    /// 단어리스트 필터(.all/.favorite/.wrong). 전체·즐겨찾기 루트탭과 동기화됨.
    @State private var wordFilter: WordListFilter = .all

    enum Tab: Hashable {
        case all, favorite, search, game, settings

        var label: String {
            switch self {
            case .all:      return "전체"
            case .favorite: return "즐겨찾기"
            case .search:   return "검색"
            case .game:     return "게임"
            case .settings: return "설정"
            }
        }

        var icon: String {
            switch self {
            case .all:      return "list.bullet"
            case .favorite: return "star"
            case .search:   return "magnifyingglass"
            case .game:     return "gamecontroller"
            case .settings: return "gearshape"
            }
        }

        var iconFilled: String {
            switch self {
            case .all:      return "list.bullet"
            case .favorite: return "star.fill"
            case .search:   return "magnifyingglass"
            case .game:     return "gamecontroller.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Render all tabs simultaneously so their @State survives tab switches.
            // Show only the active one via opacity + hitTesting.
            // 전체/즐겨찾기 루트탭은 단일 WordListView 인스턴스를 공유하되,
            // wordFilter 값을 통해 표시 내용을 구분한다 (세그먼트와 루트탭이 양방향 동기화됨).
            ZStack {
                WordListView(filter: $wordFilter) { f in
                    withAnimation(.easeOut(duration: 0.12)) {
                        selected = (f == .favorite) ? .favorite : .all
                    }
                }
                .opacity(selected == .all || selected == .favorite ? 1 : 0)
                .allowsHitTesting(selected == .all || selected == .favorite)

                SearchView()
                    .opacity(selected == .search ? 1 : 0)
                    .allowsHitTesting(selected == .search)
                GameView(path: $gamePath)
                    .opacity(selected == .game ? 1 : 0)
                    .allowsHitTesting(selected == .game)
                SettingsView()
                    .opacity(selected == .settings ? 1 : 0)
                    .allowsHitTesting(selected == .settings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Divider above tabbar
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1 / displayScale)

            // Custom tabbar
            HStack(spacing: 0) {
                ForEach([Tab.all, .favorite, .search, .game, .settings], id: \.self) { tab in
                    tabItem(tab)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
            .background(Theme.surface)
        }
        .background(Theme.surface)
        .ignoresSafeArea(.keyboard)
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

    private func tabItem(_ tab: Tab) -> some View {
        let isActive = selected == tab
        return Button {
            // Pop-to-root only when the Game tab is tapped while ALREADY active.
            //   · Game tab (sub-view) → Game tab : pop to GameView root.
            //   · Game tab (sub-view) → Search → Game tab : KEEP the sub-view
            //     (user is switching back, not requesting pop).
            if tab == .game && selected == .game {
                gamePath = NavigationPath()
            }
            // 전체/즐겨찾기 루트탭 탭 → 단어리스트 필터도 함께 전환 (세그먼트와 양방향 동기화).
            withAnimation(.easeInOut(duration: 0.15)) {
                if tab == .all {
                    wordFilter = .all
                } else if tab == .favorite {
                    wordFilter = .favorite
                }
            }
            withAnimation(.easeOut(duration: 0.12)) {
                selected = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isActive ? tab.iconFilled : tab.icon)
                    .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Theme.ink : Theme.muted)
                    .frame(height: 20)
                Text(tab.label)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? Theme.ink : Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
