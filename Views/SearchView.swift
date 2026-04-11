import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var context
    @State private var query: String = ""
    @Query private var allWords: [Word]

    @State private var showBulkAlert = false
    @State private var bulkMessage = ""

    var results: [Word] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return allWords.filter { w in
            w.english.lowercased().contains(q) ||
            w.meaning.lowercased().contains(q) ||
            w.pronunciation.lowercased().contains(q) ||
            w.example.lowercased().contains(q) ||
            w.exampleKo.lowercased().contains(q)
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
            .navigationTitle("검색")
            .searchable(text: $query, prompt: "단어 또는 뜻 검색")
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
