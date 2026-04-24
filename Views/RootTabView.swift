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
    @State private var searchResetTrigger: Bool = false

    /// 한 번이라도 열린 탭을 기록 — 최초 열린 순간에만 뷰를 생성하고
    /// 이후에는 opacity 로 숨기되, 아직 한 번도 열리지 않은 탭은 생성 자체를 하지 않는다.
    /// 이렇게 하면 앱 시작 시 @Query 가 4개 동시 활성화되는 것을 막는다.
    @State private var appeared: Set<Tab> = [.all, .favorite]  // 단어 리스트는 기본

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

    /// 단어 리스트 탭이 활성인지
    private var isWordTab: Bool { selected == .all || selected == .favorite }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // 단어 리스트: 항상 생성됨 (기본 탭)
                WordListView(filter: $wordFilter) { f in
                    withAnimation(.easeOut(duration: 0.12)) {
                        selected = (f == .favorite) ? .favorite : .all
                    }
                }
                .opacity(isWordTab ? 1 : 0)
                .allowsHitTesting(isWordTab)

                // 나머지 탭: 최초 선택 시에만 생성, 이후 opacity로 관리
                lazyTab(.search) { SearchView(resetTrigger: $searchResetTrigger) }
                lazyTab(.game)   { GameView(path: $gamePath) }
                lazyTab(.settings) { SettingsView() }
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

    /// 탭 내용이 최초 선택될 때만 생성되고 이후에는 opacity 로 관리되는 lazy 탭 헬퍼.
    @ViewBuilder
    private func lazyTab<Content: View>(_ tab: Tab, @ViewBuilder content: () -> Content) -> some View {
        if appeared.contains(tab) {
            content()
                .opacity(selected == tab ? 1 : 0)
                .allowsHitTesting(selected == tab)
        }
    }

    private func tabItem(_ tab: Tab) -> some View {
        let isActive = selected == tab
        return Button {
            // 탭이 처음 열리면 appeared 에 기록
            appeared.insert(tab)

            // Pop-to-root only when the Game tab is tapped while ALREADY active.
            if tab == .game && selected == .game {
                gamePath = NavigationPath()
            }
            // 검색 탭을 이미 활성인 상태에서 다시 누르면 검색 초기화
            if tab == .search && selected == .search {
                searchResetTrigger.toggle()
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
