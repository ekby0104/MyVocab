import SwiftUI
import SwiftData

// MARK: - Filter

enum WordListFilter: String, CaseIterable, Identifiable {
    case all      = "전체"
    case favorite = "즐겨찾기"
    case wrong    = "틀린 단어"
    var id: String { rawValue }
}

// MARK: - WordListView (목업 구조 · ScrollView + custom cards)

struct WordListView: View {
    /// 현재 필터(전체/즐겨찾기/틀린 단어). 부모(RootTabView)와 공유.
    @Binding var filter: WordListFilter
    @Binding var wordListPath: NavigationPath

    /// 세그먼트에서 .all 또는 .favorite 이 선택됐을 때 부모가 루트탭을 동기화할 수 있도록
    /// 호출되는 콜백. .wrong 은 호출되지 않음.
    var onSelectMainFilter: (WordListFilter) -> Void = { _ in }

    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]
    @Environment(\.modelContext) private var context

    @State private var sortOrder: SortOrder = .newest
    @State private var showAdd = false

    // 캐시된 정렬/필터 결과 — body 당 1회만 계산
    @State private var cachedList: [Word] = []
    @State private var cachedCount: Int = 0

    // 뜻 보이기/숨기기
    @AppStorage("wordList.showMeaning") private var showMeaning: Bool = true

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest        = "최신순"
        case alphabet      = "알파벳"
        case alphabetDesc  = "알파벳 역순"
        case favorite      = "즐겨찾기 우선"
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

    // MARK: Derived

    private func rebuildList() {
        let base: [Word]
        switch filter {
        case .all:      base = words
        case .favorite: base = words.filter(\.isFavorite)
        case .wrong:    base = words.filter { $0.isWrong || $0.wrongCount > 0 }
        }
        cachedList = sortWords(base)
        cachedCount = cachedList.count
    }

    private func sortWords(_ list: [Word]) -> [Word] {
        var list = list
        switch sortOrder {
        case .newest:       list.sort { $0.createdAt > $1.createdAt }
        case .alphabet:     list.sort { $0.english.localizedCaseInsensitiveCompare($1.english) == .orderedAscending }
        case .alphabetDesc: list.sort { $0.english.localizedCaseInsensitiveCompare($1.english) == .orderedDescending }
        case .favorite:
            list.sort { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
                return lhs.english.localizedCaseInsensitiveCompare(rhs.english) == .orderedAscending
            }
        case .wrong:
            list.sort { lhs, rhs in
                if lhs.isWrong != rhs.isWrong { return lhs.isWrong && !rhs.isWrong }
                if lhs.wrongCount != rhs.wrongCount { return lhs.wrongCount > rhs.wrongCount }
                return lhs.english.localizedCaseInsensitiveCompare(rhs.english) == .orderedAscending
            }
        case .random: list.shuffle()
        }
        return list
    }

    // MARK: Body

    var body: some View {
        NavigationStack(path: $wordListPath) {
            VStack(spacing: 0) {
                // 상단: 타이틀 + 아이콘 버튼 (목업 .topbar)
                topBar

                // 세그먼트: 전체 / 즐겨찾기 / 틀린 단어 (목업 .segmented)
                segmented
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                // 리스트
                if cachedList.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(cachedList) { word in
                                NavigationLink(value: word.persistentModelID) {
                                    WordCardRow(
                                        word: word,
                                        showMeaning: showMeaning,
                                        isLast: word.id == cachedList.last?.id,
                                        onToggleFavorite: { toggleFavorite(word) }
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        toggleFavorite(word)
                                    } label: {
                                        Label(
                                            word.isFavorite ? "즐겨찾기 해제" : "즐겨찾기",
                                            systemImage: word.isFavorite ? "star.slash" : "star"
                                        )
                                    }
                                    Button(role: .destructive) {
                                        delete(word)
                                    } label: {
                                        Label("삭제", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(Theme.surface)
            .navigationBarHidden(true)
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let word = words.first(where: { $0.persistentModelID == id }) {
                    WordDetailView(word: word)
                }
            }
            .sheet(isPresented: $showAdd) {
                WordEditView(mode: .add)
            }
            .onAppear { rebuildList() }
            .onChange(of: words.count) { rebuildList() }
            .onChange(of: filter)      { rebuildList() }
            .onChange(of: sortOrder)   { rebuildList() }
        }
    }

    // MARK: - Top bar (목업 .topbar)

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(filter.rawValue)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .tracking(-0.5)
            Text("\(cachedCount)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)

            Spacer()

            // 정렬
            Menu {
                Picker("정렬", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { o in
                        Label(o.rawValue, systemImage: o.iconName).tag(o)
                    }
                }
            } label: {
                iconButton(systemName: "arrow.up.arrow.down")
            }

            // 뜻 보이기 토글
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showMeaning.toggle() }
            } label: {
                iconButton(systemName: showMeaning ? "eye" : "eye.slash")
            }

            // 추가
            Button {
                showAdd = true
            } label: {
                iconButton(systemName: "plus")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func iconButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(width: 32, height: 32)
            .background(Theme.chipBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Segmented (목업 .segmented)

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(WordListFilter.allCases) { f in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { filter = f }
                    // .all / .favorite 세그먼트는 루트탭도 함께 전환. .wrong 은 로컬 필터만.
                    if f == .all || f == .favorite {
                        onSelectMainFilter(f)
                    }
                } label: {
                    Text(f.rawValue)
                        .font(.system(size: 12, weight: filter == f ? .semibold : .medium))
                        .foregroundStyle(filter == f ? Theme.ink : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(filter == f ? Theme.surface : Color.clear)
                                .shadow(color: filter == f ? Color.black.opacity(0.06) : .clear,
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

    // MARK: - Empty

    @ViewBuilder
    private var emptyState: some View {
        Spacer()
        VStack(spacing: 10) {
            Image(systemName: filter == .favorite ? "star" : (filter == .wrong ? "xmark.circle" : "text.book.closed"))
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.muted)
            Text(emptyTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(emptySub)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding()
        Spacer()
    }

    private var emptyTitle: String {
        switch filter {
        case .all:      return "단어가 없습니다"
        case .favorite: return "즐겨찾기가 없습니다"
        case .wrong:    return "틀린 단어가 없습니다"
        }
    }

    private var emptySub: String {
        switch filter {
        case .all:      return "우상단 + 버튼으로 추가하거나\n설정에서 네이버 동기화하세요."
        case .favorite: return "카드에서 별 아이콘을 눌러 추가하세요."
        case .wrong:    return "퀴즈/플래시카드에서 틀린 단어가 모입니다."
        }
    }

    // MARK: - Actions

    private func toggleFavorite(_ word: Word) {
        word.isFavorite.toggle()
        try? context.save()
        if filter == .favorite { rebuildList() }
    }

    private func delete(_ word: Word) {
        context.delete(word)
        try? context.save()
        rebuildList()
    }
}

// MARK: - Word Card Row (목업 .word-card)

struct WordCardRow: View {
    @Environment(\.displayScale) private var displayScale
    let word: Word
    var showMeaning: Bool = true
    var isLast: Bool = true
    /// 우측 별 아이콘 탭 시 호출되는 콜백 (즐겨찾기 토글).
    var onToggleFavorite: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // body
            VStack(alignment: .leading, spacing: 0) {
                // en-row: en + pos (baseline, wrap)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(word.english)
                        .font(.vocabTitle)
                        .foregroundStyle(Theme.ink)
                        .tracking(-0.1)
                    if !word.partOfSpeech.isEmpty {
                        Text(word.partOfSpeech)
                            .font(.vocabPos)
                            .foregroundStyle(Theme.muted)
                    }
                }

                // pron
                if !word.pronunciation.isEmpty {
                    Text(word.pronunciation)
                        .font(.vocabMuted)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }

                // ko (뜻)
                if showMeaning, !word.meaning.isEmpty {
                    Text(word.meaning)
                        .font(.vocabBody)
                        .foregroundStyle(Theme.ink.opacity(0.75))
                        .lineLimit(2)
                        .padding(.top, 2)
                }

                // chips (ko 아래)
                if !chips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(chips.indices, id: \.self) { i in
                            chips[i]
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // star (우측) — 탭하면 즐겨찾기 토글 (NavigationLink 로의 전파는 차단됨)
            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: word.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(word.isFavorite ? Theme.favorite : Theme.line)
                    .padding(.top, 1)
                    .padding(.leading, 10)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Theme.line)
                    .frame(height: 1 / displayScale)
            }
        }
        .contentShape(Rectangle())
    }

    /// 목업 칩 규칙 재현
    private var chips: [VocabChip] {
        var result: [VocabChip] = []
        if word.srsLevel >= 5 {
            result.append(VocabChip(text: "Mastered · Lv.\(word.srsLevel)", kind: .neutral))
        } else if word.lastReviewedAt == nil {
            result.append(VocabChip(text: "NEW", kind: .correct))
        }
        if word.wrongCount > 0 {
            result.append(VocabChip(text: "✗ \(word.wrongCount)", kind: .wrong))
        }
//        if word.isFavorite {
//            result.append(VocabChip(text: "즐겨찾기", kind: .favorite))
//        }
        return result
    }
}
