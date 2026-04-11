import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var context
    @State private var query: String = ""
    @Query private var allWords: [Word]

    @State private var showBulkAlert = false
    @State private var bulkMessage = ""

    enum SearchScope: String, CaseIterable, Identifiable {
        case all = "전체"
        case word = "단어"
        case example = "예문"
        var id: String { rawValue }
    }

    @State private var searchScope: SearchScope = .all

    var results: [Word] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        let q = raw.lowercased()

        // 와일드카드 매칭 함수
        let match: (String) -> Bool = { text in
            let t = text.lowercased()
            if q.hasPrefix("*") && q.hasSuffix("*") && q.count > 2 {
                return t.contains(String(q.dropFirst().dropLast()))
            } else if q.hasPrefix("*") {
                return t.hasSuffix(String(q.dropFirst()))
            } else if q.hasSuffix("*") {
                return t.hasPrefix(String(q.dropLast()))
            } else {
                return t.contains(q)
            }
        }

        return allWords.filter { w in
            switch searchScope {
            case .all:
                return match(w.english) || match(w.meaning) ||
                       match(w.pronunciation) ||
                       match(w.example) || match(w.exampleKo)
            case .word:
                return match(w.english) || match(w.meaning) ||
                       match(w.pronunciation)
            case .example:
                return match(w.example) || match(w.exampleKo)
            }
        }
    }

    // 현재 검색 결과가 모두 즐겨찾기 상태인지
    private var allFavorited: Bool {
        !results.isEmpty && results.allSatisfy(\.isFavorite)
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ContentUnavailableView(
                        "검색",
                        systemImage: "magnifyingglass",
                        description: Text("한글 또는 영어로 검색할 수 있습니다.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        // 일괄 작업 헤더
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
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        delete(word)
                                    } label: {
                                        Label("삭제", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.accentColor)
                        Text("검색")
                    }
                    .font(.headline)
                }
            }
            .searchable(text: $query, prompt: "단어 또는 뜻 검색 (*로 와일드카드)")
            .searchScopes($searchScope) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .alert("완료", isPresented: $showBulkAlert) {
                Button("확인") {}
            } message: {
                Text(bulkMessage)
            }
        }
    }

    // MARK: - Actions

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
}
