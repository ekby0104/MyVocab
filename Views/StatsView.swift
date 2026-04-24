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

    private func rebuildStats() {
        totalWords = allWords.count
        favoriteCount = allWords.filter(\.isFavorite).count
        wrongWordsCount = allWords.filter(\.isWrong).count

        var correct = 0, wrong = 0, studied = 0, mastered = 0
        for w in allWords {
            correct += w.correctCount
            wrong += w.wrongCount
            if w.lastReviewedAt != nil { studied += 1 }
            if w.srsLevel >= 5 { mastered += 1 }
        }
        totalCorrect = correct
        totalWrong = wrong
        totalAttempts = correct + wrong
        accuracyPercent = totalAttempts > 0 ? Int(Double(correct) / Double(totalAttempts) * 100) : 0
        studiedCount = studied
        masteredCount = mastered

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
            LevelWordsView(level: level, allWords: allWords)
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

struct LevelWordsView: View {
    let level: Int
    let allWords: [Word]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private var words: [Word] {
        allWords.filter { $0.srsLevel == level }
            .sorted { $0.english.lowercased() < $1.english.lowercased() }
    }

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

                    Text("Lv.\(level) · \(words.count)개")
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
                        ForEach(Array(words.enumerated()), id: \.element.id) { idx, word in
                            NavigationLink { WordDetailView(word: word) } label: {
                                WordCardRow(word: word, showMeaning: true, isLast: idx == words.count - 1, onToggleFavorite: {
                                    word.isFavorite.toggle()
                                    try? context.save()
                                })
                            }
                            .buttonStyle(.plain)
                        }

                        if words.isEmpty {
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
        }
    }
}
