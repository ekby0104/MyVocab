import SwiftUI
import SwiftData

struct WordListView: View {
    let favoritesOnly: Bool

    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]
    @Environment(\.modelContext) private var context
    @State private var showAdd = false

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest        = "최신순"
        case alphabet      = "알파벳"
        case alphabetDesc  = "알파벳 역순"
        case favorite      = "즐겨찾기"
        case wrong         = "오답 순"
        case random        = "랜덤"
        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .newest:       return "clock"
            case .alphabet:     return "textformat.abc"
            case .alphabetDesc: return "textformat.abc.dottedunderline"
            case .favorite:     return "star.fill"
            case .wrong:        return "xmark.circle"
            case .random:       return "shuffle"
            }
        }
    }

    @State private var sortOrder: SortOrder = .newest

    var displayed: [Word] {
        var list = favoritesOnly ? words.filter(\.isFavorite) : words
        switch sortOrder {
        case .newest:
            list.sort { $0.createdAt > $1.createdAt }
        case .alphabet:
            list.sort { $0.english.lowercased() < $1.english.lowercased() }
        case .alphabetDesc:
            list.sort { $0.english.lowercased() > $1.english.lowercased() }
        case .favorite:
            // 즐겨찾기 먼저, 그 안에서는 알파벳순
            list.sort { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite {
                    return lhs.isFavorite && !rhs.isFavorite
                }
                return lhs.english.lowercased() < rhs.english.lowercased()
            }
        case .wrong:
            // 오답 횟수 많은 순, 같으면 알파벳순
            list.sort { lhs, rhs in
                if lhs.wrongCount != rhs.wrongCount {
                    return lhs.wrongCount > rhs.wrongCount
                }
                return lhs.english.lowercased() < rhs.english.lowercased()
            }
        case .random:
            list.shuffle()
        }
        return list
    }

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    ContentUnavailableView(
                        "단어가 없습니다",
                        systemImage: "text.book.closed",
                        description: Text("우상단 + 버튼으로 추가하거나\n설정에서 네이버 동기화하세요.")
                    )
                } else if favoritesOnly && displayed.isEmpty {
                    ContentUnavailableView(
                        "즐겨찾기가 없습니다",
                        systemImage: "star",
                        description: Text("단어를 왼쪽으로 스와이프해서 추가하세요.")
                    )
                } else {
                    List {
                        ForEach(displayed) { word in
                            NavigationLink { WordDetailView(word: word) } label: {
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
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(favoritesOnly ? "⭐ 즐찾 (\(displayed.count))" : "📚 전체 (\(words.count))")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("정렬", selection: $sortOrder) {
                            ForEach(SortOrder.allCases) { order in
                                Label(order.rawValue, systemImage: order.iconName)
                                    .tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
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
}

struct WordRow: View {
    let word: Word
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(word.english).font(.headline)
                if !word.partOfSpeech.isEmpty {
                    Text(word.partOfSpeech)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if word.wrongCount > 0 {
                    Text("✗\(word.wrongCount)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                }
                if word.isFavorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
                if word.isWrong {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
                }
            }
            if !word.pronunciation.isEmpty {
                Text(word.pronunciation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !word.meaning.isEmpty {
                Text(word.meaning)
                    .font(.subheadline)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
