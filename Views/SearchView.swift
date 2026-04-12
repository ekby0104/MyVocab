import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var context
    @State private var query: String = ""
    @Query private var allWords: [Word]

    @State private var showBulkAlert = false
    @State private var bulkMessage = ""

    /// 와일드카드 검색 여부 (*, ? 포함)
    private var hasWildcard: Bool {
        query.contains("*") || query.contains("?")
    }

    /// 와일드카드 → 정규식 변환
    /// * = 하나 이상의 임의 문자, ? = 정확히 한 글자
    /// 나머지 정규식 특수문자는 이스케이프
    private func wildcardRegex(from pattern: String) -> NSRegularExpression? {
        var regex = ""
        for ch in pattern {
            switch ch {
            case "*":
                regex += ".+"        // 1개 이상
            case "?":
                regex += "."         // 정확히 1개
            case ".", "(", ")", "[", "]", "{", "}", "^", "$",
                 "|", "\\", "+":
                regex += "\\\(ch)"   // 정규식 특수문자 이스케이프
            default:
                regex += String(ch)
            }
        }
        // 전체 매칭이 아닌 부분 매칭 (wildcard 위치가 의미 있음)
        return try? NSRegularExpression(
            pattern: "^" + regex + "$",
            options: [.caseInsensitive]
        )
    }

    var results: [Word] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        if hasWildcard {
            // 와일드카드 모드: 영어/한글 뜻만 대상으로 패턴 매칭
            guard let regex = wildcardRegex(from: q) else { return [] }
            return allWords.filter { w in
                matches(regex, w.english) || matches(regex, w.meaning)
            }
        } else {
            // 일반 모드: 부분 일치 검색
            let lower = q.lowercased()
            return allWords.filter { w in
                w.english.lowercased().contains(lower) ||
                w.meaning.lowercased().contains(lower) ||
                w.pronunciation.lowercased().contains(lower) ||
                w.example.lowercased().contains(lower) ||
                w.exampleKo.lowercased().contains(lower)
            }
        }
    }

    private func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private var allFavorited: Bool {
        !results.isEmpty && results.allSatisfy(\.isFavorite)
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ContentUnavailableView {
                        Label("검색", systemImage: "magnifyingglass")
                    } description: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("한글 또는 영어로 검색할 수 있습니다.")
                            Text("와일드카드:")
                                .font(.caption.bold())
                                .padding(.top, 4)
                            Text("• **ab\\*** — ab로 시작하는 단어")
                            Text("• **\\*ing** — ing로 끝나는 단어")
                            Text("• **c\\*t** — c와 t 사이에 글자 포함")
                            Text("• **c?t** — cat, cot처럼 3글자")
                        }
                        .font(.caption)
                        .multilineTextAlignment(.leading)
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
                        } header: {
                            if hasWildcard {
                                Text("패턴 검색: \(query)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("검색")
            .searchable(text: $query, prompt: "단어 검색 (*, ? 사용 가능)")
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
}
