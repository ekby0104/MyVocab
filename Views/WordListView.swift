import SwiftUI
import SwiftData
import Combine

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

    /// @Query가 이미 createdAt 역순으로 정렬해서 가져온다.
    /// `.newest` 정렬일 때는 이 결과를 그대로 쓰고 메모리 재정렬을 생략한다.
    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var sortOrder: SortOrder = .newest
    @State private var showAdd = false

    // 캐시된 정렬/필터 결과 — body 당 1회만 계산.
    // chips 까지 함께 캐시해서 셀 렌더링 시 Calendar.dateComponents 반복 호출을 막는다.
    @State private var cachedList: [RowVM] = []
    @State private var cachedCount: Int = 0

    /// 첫 paint 가 완료되었는지 (lazy 시작 최적화).
    /// false 인 동안 ScrollView 자리에 가벼운 placeholder 만 표시 → 시작 paint 즉시 끝남.
    /// true 가 되면 다음 런루프에 rebuildList() 가 한 번 돌아 cachedList 채워짐.
    @State private var didInitialBuild: Bool = false

    /// rebuildList() 가 마지막으로 반영한 단어 수. words.count 변화 감지에서
    /// 최초 빌드와 중복으로 다시 도는 것을 막기 위한 가드.
    @State private var lastBuiltCount: Int = -1

    // 뜻 보이기/숨기기
    @AppStorage("wordList.showMeaning") private var showMeaning: Bool = true

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest        = "최신순"
        case alphabet      = "알파벳"
        case alphabetDesc  = "알파벳 역순"
        case favorite      = "즐겨찾기 우선"
        case hard          = "어려움 우선"
        case wrong         = "오답 순"
        case dueDate       = "복습 임박순"
        case random        = "랜덤"
        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .newest:       return "clock"
            case .alphabet:     return "textformat.abc"
            case .alphabetDesc: return "textformat.abc.dottedunderline"
            case .favorite:     return "star.fill"
            case .hard:         return "flame.fill"
            case .wrong:        return "xmark.circle"
            case .dueDate:      return "calendar"
            case .random:       return "shuffle"
            }
        }
    }

    // MARK: Derived

    /// 행 표시용 VM (Word + 미리 계산된 chips)
    struct RowVM: Identifiable {
        let word: Word
        let chips: [VocabChip]
        var id: PersistentIdentifier { word.persistentModelID }
    }

    private func rebuildList() {
        let base: [Word]
        switch filter {
        case .all:      base = words
        case .favorite: base = words.filter(\.isFavorite)
        case .wrong:    base = words.filter { $0.isWrong || $0.wrongCount > 0 }
        }
        let sorted = sortWords(base)
        let now = Date()
        let cal = Calendar.current
        cachedList = sorted.map { RowVM(word: $0, chips: makeChips(for: $0, now: now, cal: cal)) }
        cachedCount = cachedList.count
        lastBuiltCount = words.count
    }

    /// 정렬에 영향 없는 토글(즐겨찾기/어려움/삭제) 후 - 셀 chips만 갱신.
    private func refreshChipsForRow(_ word: Word) {
        guard let idx = cachedList.firstIndex(where: { $0.word.persistentModelID == word.persistentModelID }) else { return }
        let now = Date()
        let cal = Calendar.current
        cachedList[idx] = RowVM(word: word, chips: makeChips(for: word, now: now, cal: cal))
    }

    /// 칩 계산 - 부모(rebuildList)에서 한 번만 수행
    private func makeChips(for word: Word, now: Date, cal: Calendar) -> [VocabChip] {
        var result: [VocabChip] = []
        if word.srsLevel >= 5 {
            result.append(VocabChip(text: "Mastered · Lv.\(word.srsLevel)", kind: .neutral))
        } else if word.lastReviewedAt == nil {
            result.append(VocabChip(text: "NEW", kind: .correct))
        } else if let info = dueInfo(for: word, now: now, cal: cal) {
            result.append(VocabChip(text: info.label, kind: info.kind))
        }
        if word.wrongCount > 0 {
            result.append(VocabChip(text: "✗ \(word.wrongCount)", kind: .wrong))
        }
        if word.isHard {
            result.append(VocabChip(text: "🔥", kind: .hard))
        }
        return result
    }

    private func dueInfo(for word: Word, now: Date, cal: Calendar) -> (label: String, kind: VocabChip.Kind)? {
        guard let next = word.nextReviewDate else { return nil }
        if next <= now { return ("복습 가능", .correct) }

        let startOfToday = cal.startOfDay(for: now)
        let startOfDueDay = cal.startOfDay(for: next)
        let days = cal.dateComponents([.day], from: startOfToday, to: startOfDueDay).day ?? 0

        if days == 0 {
            let comps = cal.dateComponents([.hour, .minute], from: now, to: next)
            let h = comps.hour ?? 0
            let m = comps.minute ?? 0
            let label: String
            if h > 0 { label = "\(h)시간 \(m)분 후" }
            else if m > 0 { label = "\(m)분 후" }
            else { label = "곧 복습" }
            return (label, .info)
        }
        if days == 1 { return ("내일", .favorite) }
        if days < 7 { return ("\(days)일 후", .neutral) }
        return ("\(days / 7)주 후", .neutral)
    }

    /// 복습 임박순 정렬 우선순위 (낮을수록 위)
    private func duePriority(_ word: Word) -> Int {
        guard let next = word.nextReviewDate else { return 0 }   // NEW
        return next <= Date() ? 1 : 2
    }

    private func sortWords(_ list: [Word]) -> [Word] {
        // 최적화: .newest 는 @Query 가 이미 정렬해서 줬으므로 재정렬 생략.
        // base == words 인 경우(.all 필터)에는 그대로 반환.
        if sortOrder == .newest {
            return list
        }
        var list = list
        switch sortOrder {
        case .newest:
            break  // 위에서 처리됨
        case .alphabet:     list.sort { $0.english.localizedCaseInsensitiveCompare($1.english) == .orderedAscending }
        case .alphabetDesc: list.sort { $0.english.localizedCaseInsensitiveCompare($1.english) == .orderedDescending }
        case .favorite:
            list.sort { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
                return lhs.english.localizedCaseInsensitiveCompare(rhs.english) == .orderedAscending
            }
        case .hard:
            list.sort { lhs, rhs in
                if lhs.isHard != rhs.isHard { return lhs.isHard && !rhs.isHard }
                return lhs.english.localizedCaseInsensitiveCompare(rhs.english) == .orderedAscending
            }
        case .wrong:
            list.sort { lhs, rhs in
                if lhs.isWrong != rhs.isWrong { return lhs.isWrong && !rhs.isWrong }
                if lhs.wrongCount != rhs.wrongCount { return lhs.wrongCount > rhs.wrongCount }
                return lhs.english.localizedCaseInsensitiveCompare(rhs.english) == .orderedAscending
            }
        case .dueDate:
            list.sort { lhs, rhs in
                let lp = duePriority(lhs)
                let rp = duePriority(rhs)
                if lp != rp { return lp < rp }
                switch (lhs.nextReviewDate, rhs.nextReviewDate) {
                case (nil, nil):
                    return lhs.english.localizedCaseInsensitiveCompare(rhs.english) == .orderedAscending
                case let (l?, r?):
                    if l != r { return l < r }
                    return lhs.english.localizedCaseInsensitiveCompare(rhs.english) == .orderedAscending
                default:
                    return false
                }
            }
        case .random: list.shuffle()
        }
        return list
    }

    // MARK: Body

    var body: some View {
        NavigationStack(path: $wordListPath) {
            VStack(spacing: 0) {
                topBar
                segmented
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                // 첫 paint 가 끝나기 전: 가벼운 placeholder.
                // 첫 paint 끝난 직후 onAppear 에서 rebuildList() 를 다음 런루프로 미뤄 실행.
                // 이로써 NavigationStack 자체는 즉시 표시되고, 1635개 chips 계산은 다음 프레임에서 처리.
                if !didInitialBuild {
                    initialPlaceholder
                } else if cachedList.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(cachedList.enumerated()), id: \.element.id) { idx, row in
                                NavigationLink(value: row.word.persistentModelID) {
                                    WordCardRow(
                                        word: row.word,
                                        chips: row.chips,
                                        showMeaning: showMeaning,
                                        isLast: idx == cachedList.count - 1,
                                        onToggleFavorite: { toggleFavorite(row.word) },
                                        onToggleHard: { toggleHard(row.word) }
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        toggleFavorite(row.word)
                                    } label: {
                                        Label(
                                            row.word.isFavorite ? "즐겨찾기 해제" : "즐겨찾기",
                                            systemImage: row.word.isFavorite ? "star.slash" : "star"
                                        )
                                    }
                                    Button {
                                        toggleHard(row.word)
                                    } label: {
                                        Label(
                                            row.word.isHard ? "어려움 해제" : "어려움 표시",
                                            systemImage: row.word.isHard ? "flame.fill" : "flame"
                                        )
                                    }
                                    Button(role: .destructive) {
                                        delete(row.word)
                                    } label: {
                                        Label("삭제", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .scrollIndicators(.visible)
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
            .onAppear {
                // 첫 paint 후에만 rebuildList() 실행 — 시작 화면이 즉시 뜨도록.
                if !didInitialBuild {
                    // 다음 런루프로 미룸: 현재 paint 가 끝난 뒤 메인 큐에서 실행.
                    DispatchQueue.main.async {
                        rebuildList()
                        didInitialBuild = true
                    }
                }
            }
            // 첫 paint 전(!didInitialBuild)에는 words 를 읽지 않아 @Query fetch 가
            // 첫 프레임을 막지 않도록 게이팅한다. didInitialBuild 가 true 가 된 뒤에만
            // 실제 words.count 를 구독 → fetch 는 onAppear 의 다음 런루프(첫 paint 이후)에서 발생.
            .onChange(of: didInitialBuild ? words.count : -1) { _, newValue in
                // 단어 추가/삭제 시 즉시 재계산. 최초 빌드 직후의 중복 호출은 lastBuiltCount 로 차단.
                guard didInitialBuild, newValue != lastBuiltCount else { return }
                rebuildList()
            }
            .onChange(of: filter) {
                if didInitialBuild { rebuildList() }
            }
            .onChange(of: sortOrder) {
                if didInitialBuild { rebuildList() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    SaveScheduler.shared.flush(context: context)
                }
            }
        }
    }

    // MARK: - Initial placeholder (시작 시 첫 paint 를 즉시 끝내기 위한 가벼운 자리표시자)

    private var initialPlaceholder: some View {
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
                .tint(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    //
    // 최적화 포인트:
    // 1) 정렬에 영향을 주는 sortOrder일 때만 전체 재정렬
    // 2) 즐겨찾기 탭에서 즐겨찾기 해제하면 해당 행은 목록에서 제거
    // 3) 그 외에는 cachedList의 해당 row만 chips 갱신
    // 4) context.save()는 SaveScheduler에 위임 → 1초 debounce

    private func toggleFavorite(_ word: Word) {
        word.isFavorite.toggle()
        SaveScheduler.shared.scheduleSave(context: context)

        if filter == .favorite && !word.isFavorite {
            cachedList.removeAll { $0.word.persistentModelID == word.persistentModelID }
            cachedCount = cachedList.count
            return
        }
        if sortOrder == .favorite {
            rebuildList()
            return
        }
        refreshChipsForRow(word)
    }

    private func toggleHard(_ word: Word) {
        word.isHard.toggle()
        SaveScheduler.shared.scheduleSave(context: context)

        if sortOrder == .hard {
            rebuildList()
            return
        }
        refreshChipsForRow(word)
    }

    private func delete(_ word: Word) {
        context.delete(word)
        try? context.save()
        SaveScheduler.shared.cancel()
        rebuildList()
    }
}

// MARK: - Save Scheduler
//
// 즐겨찾기/어려움 토글이 빠르게 연속될 때 매번 디스크에 쓰지 않도록 debounce.
// - 1초 이내 추가 호출이 들어오면 타이머 reset
// - 1초 정적 상태가 되면 한 번만 context.save()
// - 백그라운드 진입 / 명시적 flush 시 즉시 저장
@MainActor
final class SaveScheduler {
    static let shared = SaveScheduler()
    private var workItem: DispatchWorkItem?
    private weak var pendingContext: ModelContext?

    private init() {}

    func scheduleSave(context: ModelContext, delay: TimeInterval = 1.0) {
        workItem?.cancel()
        pendingContext = context

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.flush(context: context)
        }
        workItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func flush(context: ModelContext? = nil) {
        workItem?.cancel()
        workItem = nil
        let ctx = context ?? pendingContext
        if let ctx, ctx.hasChanges {
            try? ctx.save()
        }
        pendingContext = nil
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
        pendingContext = nil
    }
}

// MARK: - Word Card Row (목업 .word-card)

struct WordCardRow: View {
    @Environment(\.displayScale) private var displayScale
    let word: Word
    /// 부모에서 미리 계산된 chips. 매 렌더링마다 Calendar 호출하지 않도록 prop으로 받는다.
    var chips: [VocabChip]? = nil
    var showMeaning: Bool = true
    var isLast: Bool = true
    var onToggleFavorite: () -> Void = {}
    var onToggleHard: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
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

                if !word.pronunciation.isEmpty {
                    Text(word.pronunciation)
                        .font(.vocabMuted)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }

                if showMeaning, !word.meaning.isEmpty {
                    Text(word.meaning)
                        .font(.vocabBody)
                        .foregroundStyle(Theme.ink.opacity(0.75))
                        .lineLimit(2)
                        .padding(.top, 2)
                }

                let resolvedChips = chips ?? fallbackChips
                if !resolvedChips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(resolvedChips.indices, id: \.self) { i in
                            resolvedChips[i]
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onToggleHard()
            } label: {
                Image(systemName: word.isHard ? "flame.fill" : "flame")
                    .font(.system(size: 14))
                    .foregroundStyle(word.isHard ? Theme.hard : Theme.line)
                    .padding(.top, 1)
                    .padding(.leading, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: word.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(word.isFavorite ? Theme.favorite : Theme.line)
                    .padding(.top, 1)
                    .padding(.leading, 2)
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

    /// chips가 prop으로 주어지지 않은 경우의 fallback (구버전 호환).
    private var fallbackChips: [VocabChip] {
        var result: [VocabChip] = []
        if word.srsLevel >= 5 {
            result.append(VocabChip(text: "Mastered · Lv.\(word.srsLevel)", kind: .neutral))
        } else if word.lastReviewedAt == nil {
            result.append(VocabChip(text: "NEW", kind: .correct))
        } else if let info = dueInfo {
            result.append(VocabChip(text: info.label, kind: info.kind))
        }
        if word.wrongCount > 0 {
            result.append(VocabChip(text: "✗ \(word.wrongCount)", kind: .wrong))
        }
        if word.isHard {
            result.append(VocabChip(text: "🔥", kind: .hard))
        }
        return result
    }

    private var dueInfo: (label: String, kind: VocabChip.Kind)? {
        guard let next = word.nextReviewDate else { return nil }
        let now = Date()
        if next <= now { return ("복습 가능", .correct) }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let startOfDueDay = cal.startOfDay(for: next)
        let days = cal.dateComponents([.day], from: startOfToday, to: startOfDueDay).day ?? 0

        if days == 0 {
            let comps = cal.dateComponents([.hour, .minute], from: now, to: next)
            let h = comps.hour ?? 0
            let m = comps.minute ?? 0
            let label: String
            if h > 0 { label = "\(h)시간 \(m)분 후" }
            else if m > 0 { label = "\(m)분 후" }
            else { label = "곧 복습" }
            return (label, .info)
        }
        if days == 1 { return ("내일", .favorite) }
        if days < 7 { return ("\(days)일 후", .neutral) }
        return ("\(days / 7)주 후", .neutral)
    }
}
