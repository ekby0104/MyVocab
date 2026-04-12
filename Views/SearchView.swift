import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var context
    @State private var query: String = ""
    @State private var scope: SearchScope = .all
    @Query private var allWords: [Word]

    @State private var showBulkAlert = false
    @State private var bulkMessage = ""
    
    // 검색 기록 (최근 10개)
    @State private var history: [String] = SearchHistoryStore.load()

    enum SearchScope: String, CaseIterable, Identifiable {
        case all = "전체"
        case word = "단어"
        case example = "예문"
        var id: String { rawValue }
    }

    private var hasWildcard: Bool {
        query.contains("*") || query.contains("?")
    }

    private func wildcardRegex(from pattern: String) -> NSRegularExpression? {
        var regex = ""
        for ch in pattern {
            switch ch {
            case "*": regex += ".+"
            case "?": regex += "."
            case ".", "(", ")", "[", "]", "{", "}", "^", "$", "|", "\\", "+":
                regex += "\\\(ch)"
            default:
                regex += String(ch)
            }
        }
        return try? NSRegularExpression(
            pattern: "^" + regex + "$",
            options: [.caseInsensitive]
        )
    }

    private func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// scope에 따라 검색 대상 필드 반환
    private func searchFields(of word: Word) -> [String] {
        switch scope {
        case .all:
            return [word.english, word.meaning, word.pronunciation, word.example, word.exampleKo]
        case .word:
            return [word.english, word.meaning, word.pronunciation]
        case .example:
            return [word.example, word.exampleKo]
        }
    }

    var results: [Word] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        if hasWildcard {
            guard let regex = wildcardRegex(from: q) else { return [] }
            return allWords.filter { w in
                searchFields(of: w).contains { matches(regex, $0) }
            }
        } else {
            let lower = q.lowercased()
            return allWords.filter { w in
                searchFields(of: w).contains { $0.lowercased().contains(lower) }
            }
        }
    }

    private var allFavorited: Bool {
        !results.isEmpty && results.allSatisfy(\.isFavorite)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 검색 범위 선택
                Picker("검색 범위", selection: $scope) {
                    ForEach(SearchScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Group {
                    if query.isEmpty {
                        if history.isEmpty {
                            ContentUnavailableView {
                                Label("검색", systemImage: "magnifyingglass")
                            } description: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("한글 또는 영어로 검색할 수 있습니다.")
                                    Text("와일드카드:")
                                        .font(.caption.bold())
                                        .padding(.top, 4)
                                    Text("• ab* — ab로 시작 (뒤에 1글자 이상)")
                                    Text("• *ing — ing로 끝 (앞에 1글자 이상)")
                                    Text("• c*t — c와 t 사이에 1글자 이상")
                                    Text("• c?t — c+한글자+t (cat, cot, cut)")
                                }
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                            }
                        } else {
                            List {
                                Section {
                                    ForEach(history, id: \.self) { term in
                                        Button {
                                            query = term
                                        } label: {
                                            HStack {
                                                Image(systemName: "clock.arrow.circlepath")
                                                    .foregroundStyle(.secondary)
                                                Text(term).foregroundStyle(.primary)
                                                Spacer()
                                                Button {
                                                    removeFromHistory(term)
                                                } label: {
                                                    Image(systemName: "xmark")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .padding(6)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                } header: {
                                    HStack {
                                        Text("최근 검색")
                                        Spacer()
                                        Button("전체 삭제") { clearHistory() }
                                            .font(.caption)
                                            .textCase(nil)
                                    }
                                }
                            }
                        }
                    } else if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        List {
                            Section {
                                Button {
                                    bulkToggleFavorite()
                                } label: {
                                    HStack {
                                        Image(systemName: allFavorited ? "star.slash.fill" : "star.fill")
                                            .foregroundStyle(.yellow)
                                        Text(allFavorited
                                             ? "검색 결과 \(results.count)개 즐겨찾기 해제"
                                             : "검색 결과 \(results.count)개 모두 즐겨찾기")
                                        Spacer()
                                    }
                                }
                            }

                            Section {
                                ForEach(results) { word in
                                    NavigationLink {
                                        WordDetailView(word: word)
                                    } label: {
                                        WordRow(word: word)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button {
                                            toggleFavorite(word)
                                        } label: {
                                            Label(
                                                word.isFavorite ? "해제" : "즐겨찾기",
                                                systemImage: word.isFavorite ? "star.slash.fill" : "star.fill"
                                            )
                                        }
                                        .tint(.yellow)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            delete(word)
                                        } label: {
                                            Label("삭제", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                if hasWildcard {
                                    Text("패턴 검색: \(query) · 범위: \(scope.rawValue)")
                                } else {
                                    Text("범위: \(scope.rawValue)")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("🔍 검색")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "단어 검색 (*, ? 사용 가능)")
            .onSubmit(of: .search) {
                saveToHistory(query)
            }
            .alert("완료", isPresented: $showBulkAlert) {
                Button("확인") {}
            } message: {
                Text(bulkMessage)
            }
        }
    }

    private func toggleFavorite(_ word: Word) {
        word.isFavorite.toggle()
        try? context.save()
    }

    private func delete(_ word: Word) {
        context.delete(word)
        try? context.save()
    }

    private func bulkToggleFavorite() {
        let targets = results
        let willFavorite = !allFavorited
        for w in targets {
            w.isFavorite = willFavorite
        }
        try? context.save()
        bulkMessage = willFavorite
            ? "\(targets.count)개 단어를 즐겨찾기에 추가했어요"
            : "\(targets.count)개 단어의 즐겨찾기를 해제했어요"
        showBulkAlert = true
    }
    // MARK: - History

    private func saveToHistory(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        SearchHistoryStore.add(trimmed)
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

// MARK: - Search History Store

enum SearchHistoryStore {
    private static let key = "searchHistory.v1"
    private static let maxCount = 10

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ term: String) {
        var list = load()
        list.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        list.insert(term, at: 0)
        if list.count > maxCount {
            list = Array(list.prefix(maxCount))
        }
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
