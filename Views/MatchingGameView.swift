import SwiftUI
import SwiftData

// MARK: - MatchingGameView (목업 구조 · match-wrap / match-grid / mc)

struct MatchingGameView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Query private var allWords: [Word]

    // 시작 화면 선택
    @State private var selectedSource: SourceType = .all

    // 게임 상태
    @State private var started = false
    @State private var cards: [MatchCard] = []
    @State private var firstSelected: String? = nil
    @State private var matchedPairs: Set<String> = []
    @State private var wrongFlash: Set<String> = []
    @State private var correctFlash: Set<String> = []
    @State private var isProcessing = false

    // 타이머
    @State private var timeRemaining: TimeInterval = 30.0
    @State private var timer: Timer? = nil
    @State private var isTimeUp = false

    // 통계
    @State private var correctCount = 0
    @State private var wrongCount = 0
    @State private var gameWords: [Word] = []
    @State private var selectedWord: Word? = nil
    /// 게임 중 매칭 실패한 단어 ID들 (중복 오답 처리 방지)
    @State private var wrongWordIds: Set<String> = []
    /// 게임 중 첫 시도에 매칭 성공한 단어 ID들 (정답으로 처리할 단어)
    @State private var correctWordIds: Set<String> = []

    @State private var showGiveUpAlert = false

    private let totalPairs = 8
    @AppStorage("matchingGame.timeLimit") private var timeLimitSeconds: Int = 30
    private var timeLimit: TimeInterval { TimeInterval(timeLimitSeconds) }

    enum SourceType: String, CaseIterable, Identifiable {
        case all       = "전체 단어"
        case favorites = "즐겨찾기"
        case wrongOnly = "틀린 단어"
        case dueToday  = "오늘의 학습"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all:       return "books.vertical"
            case .favorites: return "star"
            case .wrongOnly: return "arrow.counterclockwise"
            case .dueToday:  return "calendar"
            }
        }
    }

    private func wordsForSource(_ source: SourceType) -> [Word] {
        let base = allWords.filter { !$0.english.isEmpty && !$0.meaning.isEmpty }
        switch source {
        case .all:       return base
        case .favorites: return base.filter(\.isFavorite)
        case .wrongOnly: return base.filter(\.isWrong)
        case .dueToday:
            let now = Date()
            return base.filter { w in
                if let next = w.nextReviewDate { return next <= now }
                return true
            }
        }
    }

    // 캐싱: 시작 화면에서 반복 필터링 방지
    private var sourceCounts: [SourceType: Int] {
        let base = allWords.filter { !$0.english.isEmpty && !$0.meaning.isEmpty }
        let now = Date()
        return [
            .all: base.count,
            .favorites: base.filter(\.isFavorite).count,
            .wrongOnly: base.filter(\.isWrong).count,
            .dueToday: base.filter { w in
                if let next = w.nextReviewDate { return next <= now }
                return true
            }.count
        ]
    }

    private var isCleared: Bool {
        matchedPairs.count == totalPairs && !isTimeUp
    }

    /// 못 맞춘 단어 = 정답 처리되지 않은 모든 단어 (매칭 실패 + 매칭 못한 단어)
    private var unmatchedWords: [Word] {
        gameWords.filter { !correctWordIds.contains($0.id) }
    }

    /// 맞춘 단어 = 첫 시도에 매칭 성공한 단어
    private var matchedWords: [Word] {
        gameWords.filter { correctWordIds.contains($0.id) }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if !started {
                startScreen
            } else if isCleared {
                resultScreen(success: true)
            } else if isTimeUp {
                resultScreen(success: false)
            } else {
                gameScreen
            }
        }
        .background(Theme.surface)
        .navigationBarHidden(true)
        .onDisappear { stopTimer() }
        .sheet(item: $selectedWord) { word in
            NavigationStack {
                WordDetailView(word: word)
            }
        }
        .alert("게임을 포기할까요?", isPresented: $showGiveUpAlert) {
            Button("취소", role: .cancel) {}
            Button("포기", role: .destructive) {
                stopTimer()
                dismiss()
            }
        } message: {
            Text("지금까지의 기록은 저장되지 않아요.")
        }
    }

    // MARK: - iconChip helper

    private func iconChip(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13))
            .foregroundStyle(Theme.ink)
            .frame(width: 32, height: 32)
            .background(Theme.chipBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Start screen

    private var startTopBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                iconChip("chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Text("매칭")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Spacer()

            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var enoughWords: Bool {
        (sourceCounts[selectedSource] ?? 0) >= totalPairs
    }

    private var startScreen: some View {
        VStack(spacing: 0) {
            startTopBar

            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(totalPairs)쌍 · \(Int(timeLimit))초")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(0.5)
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.chipBg)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text("단어 매칭")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .tracking(-0.3)
                            .padding(.top, 10)

                        Text("영어 · 한글 짝을 시간 안에 맞춰보세요.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    sourceSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)

                    timeSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)

                    Button { startGame() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("시작")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(enoughWords ? Theme.ink : Theme.ink.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(!enoughWords)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    if !enoughWords {
                        Text("\(totalPairs)개 이상 필요합니다 (현재 \(sourceCounts[selectedSource] ?? 0)개)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.wrong)
                            .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 24)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var sourceSection: some View {
        VStack(spacing: 8) {
            ForEach(SourceType.allCases) { source in
                sourceRow(source)
            }
        }
    }

    /// 10초 단위로 10초 ~ 120초 (2분)
    private static let timeOptions: [Int] = stride(from: 10, through: 120, by: 10).map { $0 }

    private var timeSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .frame(width: 24, height: 24)
                .background(Theme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("제한 시간")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)

            Spacer()

            Menu {
                Picker("제한 시간", selection: $timeLimitSeconds) {
                    ForEach(Self.timeOptions, id: \.self) { sec in
                        Text(timeLabel(sec)).tag(sec)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(timeLabel(timeLimitSeconds))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func timeLabel(_ sec: Int) -> String {
        if sec < 60 { return "\(sec)초" }
        if sec % 60 == 0 { return "\(sec / 60)분" }
        return "\(sec / 60)분 \(sec % 60)초"
    }

    private func sourceRow(_ source: SourceType) -> some View {
        let count = sourceCounts[source] ?? 0
        let isSelected = selectedSource == source

        return Button {
            selectedSource = source
        } label: {
            HStack(spacing: 10) {
                Image(systemName: source.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 24, height: 24)
                    .background(Theme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(source.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.muted)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.line)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.chipBg : Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Theme.ink : Theme.line, lineWidth: isSelected ? 1.2 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(count < totalPairs ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(count < totalPairs)
    }

    // MARK: - Game Screen

    /// 가로 모드 여부
    private var isLandscape: Bool { vSizeClass == .compact }

    /// 그리드 컬럼 수 (가로: 8, 세로: 4)
    private var gridColumns: Int { isLandscape ? 8 : 4 }

    private var gameScreen: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button { showGiveUpAlert = true } label: {
                    iconChip("xmark")
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 12))
                    Text(String(format: "%.1f", max(0, timeRemaining)))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(timeRemaining <= 5 ? Theme.wrong : Theme.ink)

                Spacer()

                Text("\(matchedPairs.count)/\(totalPairs)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.chipBg)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(timeRemaining <= 5 ? Theme.wrong : Theme.ink)
                        .frame(width: geo.size.width * max(0, timeRemaining / timeLimit))
                        .animation(.linear(duration: 0.1), value: timeRemaining)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 20)

            // 카드 그리드 - 사용 가능한 공간 안에서 동적 사이즈
            GeometryReader { geo in
                let columns = gridColumns
                let rows = Int(ceil(Double(cards.count) / Double(columns)))
                let spacing: CGFloat = 5
                let cardWidth = floor((geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
                let cardHeight = floor((geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))

                VStack(spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<columns, id: \.self) { col in
                                let idx = row * columns + col
                                if idx < cards.count {
                                    cardButton(cards[idx], width: cardWidth, height: cardHeight)
                                } else {
                                    Color.clear.frame(width: cardWidth, height: cardHeight)
                                }
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, isLandscape ? 12 : 0)
            .layoutPriority(1)

            // 포기 버튼 - 가로 모드에서는 숨김 (탭바 X 버튼으로 대체)
            if !isLandscape {
                Button { giveUpGame() } label: {
                    Text("포기")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.wrong)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.wrong.opacity(0.35), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .layoutPriority(2)
            }
        }
    }

    @ViewBuilder
    private func cardButton(_ card: MatchCard, width: CGFloat, height: CGFloat) -> some View {
        let isMatched = matchedPairs.contains(card.wordId)
        let isSelected = firstSelected == card.id
        let isWrongFlash = wrongFlash.contains(card.id)
        let isCorrectFlash = correctFlash.contains(card.id)

        Button {
            guard !isProcessing, !isMatched else { return }
            selectCard(card)
        } label: {
            Text(card.text)
                .font(card.isEnglish ? .system(size: 13, weight: .bold) : .system(size: 12))
                .minimumScaleFactor(0.5)
                .lineLimit(6)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(width: width, height: height)
                .background(cardColor(
                    isMatched: isMatched,
                    isCorrectFlash: isCorrectFlash,
                    isWrongFlash: isWrongFlash,
                    isSelected: isSelected,
                    isEnglish: card.isEnglish
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isSelected ? Theme.ink :
                            isMatched ? Theme.correct.opacity(0.5) :
                            Color.clear,
                            lineWidth: 2
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .opacity(isMatched ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isMatched || isProcessing)
    }

    // MARK: - Result Screen

    private func resultScreen(success: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    iconChip("xmark")
                }
                .buttonStyle(.plain)
                Spacer()
                Text(success ? "클리어!" : "시간 초과")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    Image(systemName: success ? "trophy.fill" : "clock.badge.xmark.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(success ? Theme.favorite : Theme.wrong)
                        .padding(.top, 20)
                        .padding(.bottom, 12)

                    if success {
                        Text(String(format: "%.1f초", timeLimit - timeRemaining))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    }

                    HStack(spacing: 0) {
                        statCol(title: "정답", value: "\(correctCount)", color: Theme.correct)
                        Rectangle().fill(Theme.line).frame(width: 0.5, height: 32)
                        statCol(title: "오답", value: "\(wrongCount)", color: Theme.wrong)
                        Rectangle().fill(Theme.line).frame(width: 0.5, height: 32)
                        statCol(title: "매칭", value: "\(matchedPairs.count)/\(totalPairs)", color: Theme.ink)
                    }
                    .padding(.vertical, 12)
                    .background(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.line, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 18)

                    if !unmatchedWords.isEmpty {
                        unmatchedCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                    }

                    if !matchedWords.isEmpty {
                        matchedCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                    }

                    VStack(spacing: 8) {
                        Button { startGame() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .bold))
                                Text("다시 하기")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(.systemBackground))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        Button { dismiss() } label: {
                            Text("나가기")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Theme.line, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func statCol(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var unmatchedCard: some View {
        VStack(spacing: 0) {
            Text("못 맞춘 단어")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ForEach(Array(unmatchedWords.enumerated()), id: \.element.id) { idx, word in
                Button { selectedWord = word } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(word.english)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(word.meaning)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.line)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                if idx < unmatchedWords.count - 1 {
                    Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
                }
            }
        }
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var matchedCard: some View {
        VStack(spacing: 0) {
            Text("맞춘 단어")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ForEach(Array(matchedWords.enumerated()), id: \.element.id) { idx, word in
                Button { selectedWord = word } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(word.english)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(word.meaning)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.line)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                if idx < matchedWords.count - 1 {
                    Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
                }
            }
        }
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Game Logic

    private func startGame() {
        let pool = wordsForSource(selectedSource)
        gameWords = Array(pool.shuffled().prefix(totalPairs))

        var newCards: [MatchCard] = []
        for word in gameWords {
            newCards.append(MatchCard(wordId: word.id, text: word.english, isEnglish: true))
            newCards.append(MatchCard(wordId: word.id, text: word.meaning, isEnglish: false))
        }
        cards = newCards.shuffled()

        firstSelected = nil
        matchedPairs = []
        wrongFlash = []
        correctFlash = []
        correctCount = 0
        wrongCount = 0
        wrongWordIds = []
        correctWordIds = []
        isTimeUp = false
        isProcessing = false
        timeRemaining = timeLimit
        started = true
        startTimer()
    }

    private func selectCard(_ card: MatchCard) {
        if firstSelected == card.id {
            firstSelected = nil
            return
        }

        if let firstId = firstSelected,
           let firstCard = cards.first(where: { $0.id == firstId }),
           firstCard.isEnglish == card.isEnglish {
            firstSelected = card.id
            return
        }

        if firstSelected == nil {
            firstSelected = card.id
        } else {
            checkMatch(card)
        }
    }

    private func checkMatch(_ secondCard: MatchCard) {
        guard let firstId = firstSelected,
              let firstCard = cards.first(where: { $0.id == firstId })
        else { return }

        isProcessing = true

        if firstCard.wordId == secondCard.wordId {
            // 게임 중 한 번도 틀리지 않은 경우에만 정답으로 카운트
            if !wrongWordIds.contains(firstCard.wordId) {
                correctCount += 1
                correctWordIds.insert(firstCard.wordId)
            }
            correctFlash = [firstCard.id, secondCard.id]

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation {
                    matchedPairs.insert(firstCard.wordId)
                    correctFlash = []
                }
                firstSelected = nil
                isProcessing = false

                if matchedPairs.count == totalPairs {
                    stopTimer()
                    finalizeGame()
                }
            }
        } else {
            wrongFlash = [firstCard.id, secondCard.id]

            // 매칭 실패한 단어 추적 (실제 SRSService 처리는 게임 종료 시점에)
            let englishCard = firstCard.isEnglish ? firstCard : secondCard
            // 같은 단어를 여러 번 틀려도 오답 카운트는 1회만
            if !wrongWordIds.contains(englishCard.wordId) {
                wrongCount += 1
            }
            wrongWordIds.insert(englishCard.wordId)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation { wrongFlash = [] }
                firstSelected = nil
                isProcessing = false
            }
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 0.1
            } else {
                timeRemaining = 0
                isTimeUp = true
                stopTimer()
                finalizeGame()
            }
        }
    }

    /// 게임 종료 시 일괄 SRS 처리 (전체 성공/시간 초과/포기 모든 경우)
    private func finalizeGame() {
        for word in gameWords {
            if correctWordIds.contains(word.id) {
                SRSService.correct(word)
            } else {
                // 매칭 실패 + 매칭 못한 단어 모두 오답
                if !wrongWordIds.contains(word.id) {
                    wrongCount += 1
                }
                SRSService.wrong(word)
            }
        }
        try? context.save()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func giveUpGame() {
        stopTimer()
        isTimeUp = true
        finalizeGame()
    }

    private func cardColor(
        isMatched: Bool,
        isCorrectFlash: Bool,
        isWrongFlash: Bool,
        isSelected: Bool,
        isEnglish: Bool
    ) -> Color {
        if isMatched { return Theme.correct.opacity(0.15) }
        if isCorrectFlash { return Theme.correct.opacity(0.4) }
        if isWrongFlash { return Theme.wrong.opacity(0.4) }
        if isSelected { return Theme.link.opacity(0.3) }
        return isEnglish ? Theme.link.opacity(0.08) : Theme.favorite.opacity(0.08)
    }
}

// MARK: - Card Model

struct MatchCard: Identifiable {
    let id = UUID().uuidString
    let wordId: String
    let text: String
    let isEnglish: Bool
}
