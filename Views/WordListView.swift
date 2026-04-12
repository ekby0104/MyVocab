import SwiftUI
import SwiftData

struct WordListView: View {
    let favoritesOnly: Bool

    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]
    @Environment(\.modelContext) private var context

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "최신순"
        case alphabet = "알파벳"
        case favorite = "즐겨찾기"
        case wrongCount = "오답횟수"
        case random = "랜덤"
        var id: String { rawValue }
    }

    @State private var sortOrder: SortOrder = .newest
    @State private var hideMeaning: Bool = false

    var displayed: [Word] {
        var list = favoritesOnly ? words.filter(\.isFavorite) : words
        switch sortOrder {
        case .newest:    list.sort { $0.createdAt > $1.createdAt }
        case .alphabet:  list.sort { $0.english.lowercased() < $1.english.lowercased() }
        case .favorite:  list.sort { ($0.isFavorite ? 0 : 1) < ($1.isFavorite ? 0 : 1) }
        case .wrongCount: list.sort { $0.wrongCount > $1.wrongCount }
        case .random:    list.shuffle()
        }
        return list
    }

    private var navTitle: String {
        favoritesOnly ? "즐겨찾기 (\(displayed.count))" : "전체단어 (\(words.count))"
    }

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    ContentUnavailableView(
                        "단어가 없습니다",
                        systemImage: "text.book.closed",
                        description: Text("설정 탭에서 네이버 단어장 JSON을 불러오세요.")
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
                                WordRow(word: word, hideMeaning: hideMeaning)
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
            .contentMargins(.top, 5, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: favoritesOnly ? "star.fill" : "list.bullet")
                            .foregroundStyle(favoritesOnly ? Color.yellow : Color.accentColor)
                        Text(navTitle)
                    }
                    .font(.headline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("정렬", selection: $sortOrder) {
                            ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                        }
                        if favoritesOnly {
                            Divider()
                            Button {
                                hideMeaning.toggle()
                            } label: {
                                Label(hideMeaning ? "뜻 보기" : "뜻 숨기기", systemImage: hideMeaning ? "eye" : "eye.slash")
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
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
    var hideMeaning: Bool = false
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
                if word.isFavorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
                if word.wrongCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
                        Text("\(word.wrongCount)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            if !word.pronunciation.isEmpty {
                Text(word.pronunciation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !hideMeaning, !word.meaning.isEmpty {
                Text(word.meaning)
                    .font(.subheadline)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
