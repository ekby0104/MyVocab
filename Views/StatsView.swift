import SwiftUI
import SwiftData

// MARK: - StatsView (목업 구조 · donut-card + stat triplet + bars-card + top-wrong-card)

struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Query private var allWords: [Word]
    @State private var selectedLevel: Int? = nil

    // 캐시된 통계
    @State private var totalWords: Int = 0
    @State private var favoriteCount: Int = 0
    @State private var wrongWordsCount: Int = 0
    @State private var totalCorrect: Int = 0
    @State private var totalWrong: Int = 0
    @State private var totalAttempts: Int = 0
    @State private var accuracyPercent: Int = 0
    @State private var studiedCount: Int = 0
    @State private var masteredCount: Int = 0
    @State private var topWrongWords: [Word] = []
    @State private var levelDistribution: [(level: Int, count: Int)] = []
    @State private var maxLevelCount: Int = 1
    @State private var dueCount: Int = 0

    private func rebuildStats() {
        totalWords = allWords.count
        favoriteCount = allWords.filter(\.isFavorite).count
        wrongWordsCount = allWords.filter(\.isWrong).count

        let now = Date()
        var correct = 0, wrong = 0, studied = 0, mastered = 0, due = 0
        for w in allWords {
            correct += w.correctCount
            wrong += w.wrongCount
            if w.lastReviewedAt != nil { studied += 1 }
            if w.srsLevel >= 5 { mastered += 1 }

            // 오늘 학습할 단어: 빈 단어 제외 + 복습 예정일 도래
            if !w.english.isEmpty, !w.meaning.isEmpty {
                if let next = w.nextReviewDate {
                    if next <= now { due += 1 }
                } else {
                    due += 1   // 미학습 단어
                }
            }
        }
        totalCorrect = correct
        totalWrong = wrong
        totalAttempts = correct + wrong
        accuracyPercent = totalAttempts > 0 ? Int(Double(correct) / Double(totalAttempts) * 100) : 0
        studiedCount = studied
        masteredCount = mastered
        dueCount = due

        topWrongWords = Array(
            allWords
                .filter { $0.wrongCount > 0 }
                .sorted { $0.wrongCount > $1.wrongCount }
                .prefix(10)
        )

        let dist = SRSService.levelDistribution(from: allWords)
        levelDistribution = (0...SRSService.maxLevel).map { level in
            (level: level, count: dist[level] ?? 0)
        }
        maxLevelCount = max(1, levelDistribution.map(\.count).max() ?? 1)
    }
    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: 0) {
                    todayCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    donutCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    statTriplet
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    if totalAttempts > 0 {
                        attemptCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }

                    barsCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    if !topWrongWords.isEmpty {
                        topWrongCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    } else {
                        Spacer(minLength: 24)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.surface)
        .navigationBarHidden(true)
        .onAppear { rebuildStats() }
        .sheet(item: $selectedLevel) { level in
            // 변경: allWords를 prop으로 통째로 넘기지 않는다.
            // LevelWordsView가 자체 @Query로 가져오므로 sheet 재구성이 발생해도
            // 1635개 배열을 매번 새로 복사해 주입할 필요가 없다.
            LevelWordsView(level: level)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Theme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Text("통계")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .tracking(-0.5)
            Spacer()
            Text("\(totalWords) 단어")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Today's review card (오늘 학습할 단어)

    private var todayCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.ink)
                    .frame(width: 44, height: 44)
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("오늘의 학습")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .tracking(0.5)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(dueCount)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .tracking(-0.3)
                    Text(dueCount > 0 ? "단어 복습 가능" : "복습할 단어 없음")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Donut card

    private var donutCard: some View {
        HStack(alignment: .center, spacing: 18) {
            // Donut
            ZStack {
                Circle()
                    .stroke(Theme.chipBg, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(accuracyPercent) / 100)
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(accuracyPercent)%")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("정답률")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 100, height: 100)

            // Right column
            VStack(alignment: .leading, spacing: 8) {
                metricRow(label: "총 단어", value: "\(totalWords)")
                metricRow(label: "학습 완료", value: "\(studiedCount)")
                metricRow(label: "마스터", value: "\(masteredCount)")
                metricRow(label: "즐겨찾기", value: "\(favoriteCount)")
                metricRow(label: "틀린 단어", value: "\(wrongWordsCount)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
    }

    // MARK: - Stat triplet (정답/오답/시도)

    private var statTriplet: some View {
        HStack(spacing: 0) {
            statCol(title: "정답", value: "\(totalCorrect)", color: Theme.correct)
            Rectangle().fill(Theme.line).frame(width: 0.5, height: 34)
            statCol(title: "오답", value: "\(totalWrong)", color: Theme.wrong)
            Rectangle().fill(Theme.line).frame(width: 0.5, height: 34)
            statCol(title: "시도", value: "\(totalAttempts)", color: Theme.ink)
        }
        .padding(.vertical, 14)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statCol(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Attempt card (누적 정답/오답 바)

    private var attemptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("학습 누적")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .tracking(0.5)

            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Theme.correct)
                        .frame(width: max(0, geo.size.width * CGFloat(totalCorrect) / CGFloat(max(totalAttempts, 1))))
                    Rectangle()
                        .fill(Theme.wrong)
                        .frame(width: max(0, geo.size.width * CGFloat(totalWrong) / CGFloat(max(totalAttempts, 1))))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 10)

            HStack {
                HStack(spacing: 5) {
                    Circle().fill(Theme.correct).frame(width: 6, height: 6)
                    Text("정답 \(totalCorrect)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.correct)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Theme.wrong).frame(width: 6, height: 6)
                    Text("오답 \(totalWrong)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.wrong)
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Bars card (SRS 분포)

    private var barsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SRS 레벨 분포")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("높을수록 잘 외운 단어")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
            }

            VStack(spacing: 7) {
                ForEach(levelDistribution, id: \.level) { item in
                    barRow(item: item)
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func barRow(item: (level: Int, count: Int)) -> some View {
        Button {
            if item.count > 0 { selectedLevel = item.level }
        } label: {
            HStack(spacing: 8) {
                Text("Lv.\(item.level)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.chipBg)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(levelColor(item.level))
                            .frame(width: barWidth(item.count, container: geo.size.width))
                    }
                }
                .frame(height: 12)

                Text("\(item.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 32, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.count == 0)
        .opacity(item.count == 0 ? 0.5 : 1)
    }

    private func barWidth(_ count: Int, container: CGFloat) -> CGFloat {
        guard maxLevelCount > 0 else { return 0 }
        return container * CGFloat(count) / CGFloat(maxLevelCount)
    }

    private func levelColor(_ level: Int) -> Color {
        let intensity = min(1.0, 0.30 + Double(level) * 0.10)
        return Theme.ink.opacity(intensity)
    }

    // MARK: - Top wrong card

    private var topWrongCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("자주 틀리는 단어")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("TOP 10")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // 각 행의 bottom 에 1 physical-pixel hairline을 그려서
            // 모든 행의 구분선 두께가 일정하게 보이도록 한다.
            // (0.5pt 는 @3x 기기에서 fractional pixel 이 되어 두께가 달라 보임)
            ForEach(Array(topWrongWords.enumerated()), id: \.element.id) { idx, word in
                NavigationLink { WordDetailView(word: word) } label: {
                    topWrongRow(index: idx, word: word)
                        .overlay(alignment: .bottom) {
                            if idx < topWrongWords.count - 1 {
                                Rectangle()
                                    .fill(Theme.line)
                                    .frame(height: 1 / displayScale)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func topWrongRow(index: Int, word: Word) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .frame(width: 22, height: 22)
                .background(Theme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 1) {
                Text(word.english)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if !word.meaning.isEmpty {
                    Text(word.meaning)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("✗\(word.wrongCount)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.wrong)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.wrong.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.line)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Level Words View
//
// 최적화 포인트:
// 1) computed property `words` → @State 캐시. 매 body 호출마다 1635개 filter+sort 하던 것 제거.
// 2) chips를 부모(여기)에서 미리 계산해서 prop으로 전달 → 셀마다 dateComponents 호출 X.
// 3) 즐겨찾기 토글 시 cachedRows의 해당 행 chips만 갱신 (정렬은 english 알파벳이라 위치 안 바뀜).
// 4) SaveScheduler 로 디스크 write debounce.
// 5) 부모(StatsView)에서 prop으로 allWords 통째로 받지 않고 자체 @Query 사용 — sheet 재구성 시
//    매번 1635개 배열을 복사·주입하던 비용 제거.

struct LevelWordsView: View {
    let level: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    /// 자체 @Query — StatsView로부터 prop을 받지 않음.
    /// (StatsView가 sheet 재구성될 때마다 1635개 배열을 새로 주입하던 비용 제거)
    @Query(sort: \Word.english) private var allWords: [Word]

    /// 미리 계산된 행 캐시 — body 다시 그릴 때 1635개 filter+sort 다시 안 함.
    @State private var cachedRows: [WordListView.RowVM] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom top bar — 모달 시트에 맞게 닫기 버튼 / 타이틀 크기 확대
                HStack(spacing: 8) {
                    Button { dismiss() } label: {
                        Text("닫기")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.chipBg)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Lv.\(level) · \(cachedRows.count)개")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)

                    Spacer()

                    // 좌측 닫기 버튼과 동일 너비의 invisible placeholder
                    // (타이틀이 정확히 가운데에 오도록)
                    Text("닫기")
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .opacity(0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(cachedRows.enumerated()), id: \.element.id) { idx, row in
                            NavigationLink { WordDetailView(word: row.word) } label: {
                                WordCardRow(
                                    word: row.word,
                                    chips: row.chips,
                                    showMeaning: true,
                                    isLast: idx == cachedRows.count - 1,
                                    onToggleFavorite: { toggleFavorite(row.word) }
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if cachedRows.isEmpty {
                            Text("레벨 \(level) 단어 없음")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                                .padding(.top, 60)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
            .background(Theme.surface)
            .navigationBarHidden(true)
            .onAppear { rebuildRows() }
            // 단어 추가/삭제 / 다른 화면에서 srsLevel 변경 등 외부 변경 감지
            .onChange(of: allWords.count) { rebuildRows() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    SaveScheduler.shared.flush(context: context)
                }
            }
        }
    }

    /// 해당 레벨 단어만 추려서 chips까지 미리 계산해 캐시
    private func rebuildRows() {
        let now = Date()
        let cal = Calendar.current
        // @Query에 sort: \.english 가 걸려있으므로 추가 정렬 불필요.
        // 메모리에서 1635개를 lowercased+sort 하던 작업이 사라짐.
        cachedRows = allWords
            .filter { $0.srsLevel == level }
            .map { WordListView.RowVM(word: $0, chips: makeChips(for: $0, now: now, cal: cal)) }
    }

    /// 토글 후 해당 행의 chips만 갱신 (정렬은 영어 알파벳이라 위치 안 바뀜)
    private func refreshChipsForRow(_ word: Word) {
        guard let idx = cachedRows.firstIndex(where: { $0.word.persistentModelID == word.persistentModelID }) else { return }
        let now = Date()
        let cal = Calendar.current
        cachedRows[idx] = WordListView.RowVM(word: word, chips: makeChips(for: word, now: now, cal: cal))
    }

    private func toggleFavorite(_ word: Word) {
        word.isFavorite.toggle()
        SaveScheduler.shared.scheduleSave(context: context)
        // 정렬 키는 english라 즐겨찾기 토글로 위치가 바뀌지 않음 → 행 chips만 갱신
        refreshChipsForRow(word)
    }

    // MARK: - chips 계산 (WordListView와 동일 로직)

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
}
