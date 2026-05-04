import SwiftUI
import SwiftData

// MARK: - SearchView (목업 구조)

struct SearchView: View {
    @Environment(\.modelContext) private var context
    @Binding var resetTrigger: Bool
    @Binding var searchPath: NavigationPath
    @State private var query: String = ""
    @FocusState private var queryFocused: Bool
    @State private var scope: SearchScope = .all
    @Query private var allWords: [Word]

    @State private var showBulkAlert = false
    @State private var bulkMessage = ""

    @State private var history: [String] = SearchHistoryStore.load()

    // 캐시된 검색 결과
    @State private var cachedResults: [Word] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var hasAppeared = false

    enum SearchScope: String, CaseIterable, Identifiable {
        case all = "전체"
        case word = "단어"
        case example = "예문"
        var id: String { rawValue }
    }

    // MARK: Search logic

    private var hasWildcard: Bool { query.contains("*") || query.contains("?") }

    private func wildcardRegex(from pattern: String) -> NSRegularExpression? {
        var regex = ""
        for ch in pattern {
            switch ch {
            case "*": regex += ".*"  // 0개 이상
            case "?": regex += "."   // 정확히 1개
            case ".", "(", ")", "[", "]", "{", "}", "^", "$", "|", "\\", "+":
                regex += "\\" + String(ch)
            default: regex += String(ch)
            }
        }
        // 부분 매칭 허용: 앵커(^, $)를 붙이지 않음 → 문자열 어디든 매칭
        return try? NSRegularExpression(pattern: regex, options: [.caseInsensitive])
    }

    private func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private func searchFields(of w: Word) -> [String] {
        switch scope {
        case .all:     return [w.english, w.meaning, w.example, w.exampleKo]
        case .word:    return [w.english, w.meaning]
        case .example: return [w.example, w.exampleKo]
        }
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { cachedResults = []; return }
        if q.contains("*") || q.contains("?") {
            guard let regex = wildcardRegex(from: q) else { cachedResults = []; return }
            cachedResults = allWords.filter { searchFields(of: $0).contains { matches(regex, $0) } }
        } else {
            // 빠른 검색: localizedCaseInsensitiveContains 사용 (lowercased() 매 호출보다 빠름)
            cachedResults = allWords.filter { word in
                let fields = searchFields(of: word)
                for field in fields {
                    if field.localizedCaseInsensitiveContains(q) {
                        return true
                    }
                }
                return false
            }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            performSearch()
        }
    }

    private var allFavorited: Bool {
        !cachedResults.isEmpty && cachedResults.allSatisfy(\.isFavorite)
    }

    private var allHard: Bool {
        !cachedResults.isEmpty && cachedResults.allSatisfy(\.isHard)
    }

    // MARK: Body

    var body: some View {
        NavigationStack(path: $searchPath) {
            VStack(spacing: 0) {
                topBar
                searchBar.padding(.horizontal, 20).padding(.bottom, 12)
                segmented.padding(.horizontal, 20).padding(.bottom, 12)

                if query.isEmpty {
                    historySection
                } else if cachedResults.isEmpty {
                    emptyResults
                } else {
                    resultsList
                }
            }
            .background(Theme.surface)
            .navigationBarHidden(true)
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let word = allWords.first(where: { $0.persistentModelID == id }) {
                    WordDetailView(word: word)
                }
            }
            .onChange(of: resetTrigger) {
                query = ""
                scope = .all
                queryFocused = false
                cachedResults = []
            }
            .onChange(of: query) { scheduleSearch() }
            .onChange(of: scope) { performSearch() }
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        queryFocused = true
                    }
                }
            }
            .alert("완료", isPresented: $showBulkAlert) {
                Button("확인") {}
            } message: {
                Text(bulkMessage)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("검색")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .tracking(-0.5)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Search bar (mockup .searchbar)

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)

            TextField("단어 검색 (*, ? 사용 가능)", text: $query)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .focused($queryFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { saveToHistory(query) }

            if hasWildcard {
                Text(wildcardHint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.chipBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var wildcardHint: String {
        let q = query
        if q.hasSuffix("*") { return "· \(q.dropLast())로 시작" }
        if q.hasPrefix("*") { return "· \(q.dropFirst())로 끝남" }
        if q.contains("?") { return "· ?는 한 글자" }
        if q.contains("*") { return "· 중간 일치" }
        return ""
    }

    // MARK: - Segmented

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(SearchScope.allCases) { s in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { scope = s }
                } label: {
                    Text(s.rawValue)
                        .font(.system(size: 12, weight: scope == s ? .semibold : .medium))
                        .foregroundStyle(scope == s ? Theme.ink : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(scope == s ? Theme.surface : .clear)
                                .shadow(color: scope == s ? .black.opacity(0.06) : .clear,
                                        radius: 2, x: 0, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.chipBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - History (최근 검색 + 힌트)

    @ViewBuilder
    private var historySection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if history.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Theme.muted)
                        Text("검색어를 입력해보세요")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("단어, 발음, 예문을 모두 검색할 수 있어요")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .padding(.bottom, 8)
                }

                if !history.isEmpty {
                    HStack {
                        Text("최근 검색")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .tracking(0.5)
                        Spacer()
                        Button("모두 지우기") { clearHistory() }
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 20)

                    WrappingChips(items: history) { term in
                        query = term
                        queryFocused = true
                    } remove: { term in
                        removeFromHistory(term)
                    }
                    .padding(.horizontal, 20)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("와일드카드")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .tracking(0.5)
                    hintRow("ab*", "ab로 시작")
                    hintRow("*ing", "ing로 끝")
                    hintRow("c*t", "c와 t 사이에 0글자 이상")
                    hintRow("c?t", "c + 한 글자 + t")
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                Spacer(minLength: 20)
            }
            .padding(.top, 4)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func hintRow(_ pattern: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Text(pattern)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(desc)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Empty results

    private var emptyResults: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.muted)
            Text("검색 결과가 없습니다")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("'\(query)'에 해당하는 단어를 찾지 못했어요.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results list

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("검색 결과 · \(cachedResults.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .tracking(0.5)
                Spacer()
                Button {
                    bulkToggleHard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(allHard ? Theme.muted : Theme.hard)
                        Text(allHard ? "해제" : "선택")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.ink)
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 5)

                Button {
                    bulkToggleFavorite()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(allFavorited ? Theme.muted : Theme.favorite)
                        Text(allFavorited ? "해제" : "선택")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.ink)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(cachedResults.enumerated()), id: \.element.id) { idx, word in
                        NavigationLink(value: word.persistentModelID) {
                            WordCardRow(
                                word: word,
                                showMeaning: true,
                                isLast: idx == cachedResults.count - 1,
                                onToggleFavorite: { toggleFavorite(word) },
                                onToggleHard: { toggleHard(word) }
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { toggleFavorite(word) } label: {
                                Label(word.isFavorite ? "즐겨찾기 해제" : "즐겨찾기",
                                      systemImage: word.isFavorite ? "star.slash" : "star")
                            }
                            Button { toggleHard(word) } label: {
                                Label(word.isHard ? "어려움 해제" : "어려움 표시",
                                      systemImage: word.isHard ? "flame.fill" : "flame")
                            }
                            Button(role: .destructive) { delete(word) } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // MARK: - Actions

    private func toggleFavorite(_ word: Word) {
        word.isFavorite.toggle(); try? context.save()
    }

    private func toggleHard(_ word: Word) {
        word.isHard.toggle(); try? context.save()
    }

    private func delete(_ word: Word) {
        context.delete(word); try? context.save()
    }

    private func bulkToggleFavorite() {
        let targets = cachedResults
        let willFavorite = !allFavorited
        for w in targets { w.isFavorite = willFavorite }
        try? context.save()
        performSearch()
        bulkMessage = willFavorite
            ? "\(targets.count)개 단어를 즐겨찾기에 추가했어요"
            : "\(targets.count)개 단어의 즐겨찾기를 해제했어요"
        showBulkAlert = true
    }

    private func bulkToggleHard() {
        let targets = cachedResults
        let willHard = !allHard
        for w in targets { w.isHard = willHard }
        try? context.save()
        performSearch()
        bulkMessage = willHard
            ? "\(targets.count)개 단어를 어려움으로 표시했어요"
            : "\(targets.count)개 단어의 어려움 표시를 해제했어요"
        showBulkAlert = true
    }

    // MARK: - History store

    private func saveToHistory(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        SearchHistoryStore.add(t)
        history = SearchHistoryStore.load()
    }

    private func removeFromHistory(_ term: String) {
        SearchHistoryStore.remove(term)
        history = SearchHistoryStore.load()
    }

    private func clearHistory() {
        SearchHistoryStore.clear()
        history = []
    }
}

// MARK: - Wrapping Chips (최근 검색용)

private struct WrappingChips: View {
    let items: [String]
    var onTap: (String) -> Void
    var remove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    Button { onTap(item) } label: {
                        Text(item)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)

                    Button { remove(item) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

// MARK: - FlowLayout (iOS 16+)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > maxW {
                x = 0
                y += lineH + spacing
                lineH = 0
            }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
        return CGSize(width: maxW, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX {
                x = bounds.minX
                y += lineH + spacing
                lineH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}

// MARK: - Search History Store

enum SearchHistoryStore {
    private static let key = "searchHistory.v1"
    private static let maxCount = 20

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ term: String) {
        var list = load()
        list.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        list.insert(term, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        UserDefaults.standard.set(list, forKey: key)
    }

    static func remove(_ term: String) {
        var list = load()
        list.removeAll { $0 == term }
        UserDefaults.standard.set(list, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
