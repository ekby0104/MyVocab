import SwiftUI
import SwiftData

// MARK: - MatchingGameView (목업 구조 · match-wrap / match-grid / mc)

struct MatchingGameView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
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

    @State private var showGiveUpAlert = false

    private let totalPairs = 8
    private let timeLimit: TimeInterval = 30.0

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

    private var isCleared: Bool {
        matchedPairs.count == totalPairs && !isTimeUp
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

    private var startScreen: some View {
        VStack(spacing: 0) {
            startTopBar

            ScrollView {
                VStack(spacing: 0) {
                    // 타이틀 영역
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

                    // 단어 출처
                    sourceSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)

                    // 시작 버튼
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
                        Text("\(totalPairs)개 이상 필요합니다 (현재 \(wordsForSource(selectedSource).count)개)")
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

    private var enoughWords: Bool {
        wordsForSource(selectedSource).count >= totalPairs
    }

    private var sourceSection: some View {
        VStack(spacing: 8) {
            ForEach(SourceType.allCases) { source in
                sourceRow(source)
            }
        }
    }

    private func sourceRow(_ source: SourceType) -> some View {
        let count = wordsForSource(source).count
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Image(systemName: isSelected ? "checkmark" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.line)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.ink : Theme.line,
                            lineWidth: isSelected ? 1.2 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(count < totalPairs)
        .opacity(count < totalPairs ? 0.45 : 1)
    }

    // MARK: - Game screen

    private var gameTopBar: some View {
        HStack(spacing: 8) {
            Button { showGiveUpAlert = true } label: {
                iconChip("xmark")
            }
            .buttonStyle(.plain)

            Spacer()

            Text("매칭 · \(matchedPairs.count) / \(totalPairs)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Spacer()

            Button {
                withAnimation { cards.shuffle() }
            } label: {
                iconChip("shuffle")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var gameScreen: some View {
        VStack(spacing: 0) {
            gameTopBar

            // quiz-top: 남은 시간 + 매칭 카운트
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 11))
                    Text(String(format: "남은 시간 %.1fs", timeRemaining))
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(timeRemaining <= 5 ? Theme.wrong : Theme.ink)

                Spacer()

                Text("매칭 \(correctCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.correct)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)

            // timer-bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.chipBg)
                    Rectangle()
                        .fill(timeRemaining <= 5 ? Theme.wrong : Theme.ink)
                        .frame(width: geo.size.width * max(0, timeRemaining / timeLimit))
                        .animation(.linear(duration: 0.1), value: timeRemaining)
                }
            }
            .frame(height: 3)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            // 4×4 그리드 — 화면을 가득 채우는 균일한 카드
            GeometryReader { geo in
                let cols: CGFloat = 4
                let rows: CGFloat = 4
                let spacing: CGFloat = 6
                let cellW = (geo.size.width  - spacing * (cols - 1)) / cols
                let cellH = (geo.size.height - spacing * (rows - 1)) / rows

                LazyVGrid(columns: Array(
                    repeating: GridItem(.fixed(cellW), spacing: spacing),
                    count: Int(cols)
                ), spacing: spacing) {
                    ForEach(cards) { card in
                        cardButton(card, width: cellW, height: cellH)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            // bottom controls: 포기 / 계속 풀기 (오답 리셋)
            HStack(spacing: 8) {
                Button { showGiveUpAlert = true } label: {
                    Text("포기")
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
                .frame(maxWidth: .infinity)

                Button {
                    firstSelected = nil
                    wrongFlash = []
                } label: {
                    Text("계속 풀기")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
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
                .font(card.isEnglish
                      ? .system(size: 13, weight: .semibold)
                      : .system(size: 11))
                .foregroundStyle(cardForeground(isMatched: isMatched, isSelected: isSelected, isCorrectFlash: isCorrectFlash, isWrongFlash: isWrongFlash))
                .minimumScaleFactor(0.5)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(4)
                .frame(width: width, height: height)
                .background(cardBackground(
                    isMatched: isMatched,
                    isSelected: isSelected,
                    isCorrectFlash: isCorrectFlash,
                    isWrongFlash: isWrongFlash
                ))
                .overlay(cardBorderOverlay(
                    isMatched: isMatched,
                    isSelected: isSelected,
                    isCorrectFlash: isCorrectFlash,
                    isWrongFlash: isWrongFlash
                ))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isMatched || isProcessing)
    }

    private func cardBackground(
        isMatched: Bool,
        isSelected: Bool,
        isCorrectFlash: Bool,
        isWrongFlash: Bool
    ) -> Color {
        if isCorrectFlash { return Theme.correct.opacity(0.16) }
        if isWrongFlash   { return Theme.wrong.opacity(0.14) }
        if isMatched      { return Theme.chipBg }
        if isSelected     { return Theme.ink }
        return Theme.surface
    }

    private func cardForeground(
        isMatched: Bool,
        isSelected: Bool,
        isCorrectFlash: Bool,
        isWrongFlash: Bool
    ) -> Color {
        if isSelected   { return Color(.systemBackground) }
        if isMatched    { return Theme.muted }
        if isWrongFlash { return Theme.wrong }
        if isCorrectFlash { return Theme.correct }
        return Theme.ink
    }

    @ViewBuilder
    private func cardBorderOverlay(
        isMatched: Bool,
        isSelected: Bool,
        isCorrectFlash: Bool,
        isWrongFlash: Bool
    ) -> some View {
        if isMatched {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Theme.line)
        } else if isCorrectFlash {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.correct, lineWidth: 1)
        } else if isWrongFlash {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.wrong, lineWidth: 1)
        } else if isSelected {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.ink, lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.line, lineWidth: 0.5)
        }
    }

    // MARK: - Result screen

    private var unmatchedWords: [Word] {
        gameWords.filter { !matchedPairs.contains($0.id) }
    }

    private func resultScreen(success: Bool) -> some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 8) {
                Button { dismiss() } label: { iconChip("chevron.left") }
                    .buttonStyle(.plain)
                Spacer()
                Text("결과")
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
                    // 결과 헤더
                    VStack(spacing: 8) {
                        Image(systemName: success ? "checkmark.seal.fill" : "clock.badge.xmark")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(success ? Theme.correct : Theme.wrong)
                            .padding(.top, 8)

                        Text(success ? "클리어" : "시간 초과")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .tracking(-0.3)

                        if success {
                            Text(String(format: "%.1f초 만에 완료", timeLimit - timeRemaining))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        } else {
                            Text("다시 도전해보세요.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 18)

                    // 통계 (정답/오답/매칭률)
                    HStack(spacing: 0) {
                        statCol(title: "매칭", value: "\(correctCount)", color: Theme.correct)
                        Rectangle().fill(Theme.line).frame(width: 0.5, height: 34)
                        statCol(title: "오답", value: "\(wrongCount)", color: Theme.wrong)
                        Rectangle().fill(Theme.line).frame(width: 0.5, height: 34)
                        statCol(title: "진행", value: "\(matchedPairs.count)/\(totalPairs)", color: Theme.ink)
                    }
                    .padding(.vertical, 14)
                    .background(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.line, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)

                    // 못 맞춘 단어
                    if !unmatchedWords.isEmpty {
                        unmatchedCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                    }

                    // 액션 버튼
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
            correctCount += 1
            correctFlash = [firstCard.id, secondCard.id]

            if let word = gameWords.first(where: { $0.id == firstCard.wordId }) {
                SRSService.correct(word)
                try? context.save()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation {
                    matchedPairs.insert(firstCard.wordId)
                    correctFlash = []
                }
                firstSelected = nil
                isProcessing = false

                if matchedPairs.count == totalPairs {
                    stopTimer()
                }
            }
        } else {
            wrongCount += 1
            wrongFlash = [firstCard.id, secondCard.id]

            // 영어 카드 쪽 단어만 오답 처리
            let englishCard = firstCard.isEnglish ? firstCard : secondCard
            if let word = gameWords.first(where: { $0.id == englishCard.wordId }) {
                SRSService.wrong(word)
                try? context.save()
            }

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
                markUnmatchedAsWrong()
                isTimeUp = true
                stopTimer()
            }
        }
    }

    private func markUnmatchedAsWrong() {
        for word in gameWords where !matchedPairs.contains(word.id) {
            SRSService.wrong(word)
            wrongCount += 1
        }
        try? context.save()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Card Model

struct MatchCard: Identifiable {
    let id = UUID().uuidString
    let wordId: String
    let text: String
    let isEnglish: Bool
}
