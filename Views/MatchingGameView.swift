import SwiftUI
import SwiftData

struct MatchingGameView: View {
    @Environment(\.modelContext) private var context
    @Query private var allWords: [Word]

    // 시작 화면에서 선택
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

    private let totalPairs = 8
    private let timeLimit: TimeInterval = 30.0

    enum SourceType: String, CaseIterable, Identifiable {
        case all       = "전체 단어"
        case favorites = "즐겨찾기"
        case wrongOnly = "틀린 단어"
        case dueToday  = "오늘의 학습"
        var id: String { rawValue }

        var emoji: String {
            switch self {
            case .all:       return "📚"
            case .favorites: return "⭐"
            case .wrongOnly: return "🔄"
            case .dueToday:  return "📅"
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
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(.purple)
                    Text("단어 매칭")
                }
                .font(.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if started {
                    Button {
                        stopTimer()
                        started = false
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
            }
        }
        .onDisappear { stopTimer() }
    }

    // MARK: - Start Screen

    private var startScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 64))
                .foregroundStyle(.purple)

            Text("단어 매칭")
                .font(.title.bold())

            // 소스 선택
            VStack(spacing: 10) {
                ForEach(SourceType.allCases) { source in
                    let count = wordsForSource(source).count
                    Button {
                        selectedSource = source
                    } label: {
                        HStack {
                            Text(source.emoji).font(.title3)
                            Text(source.rawValue).font(.headline)
                            Spacer()
                            Text("\(count)개")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: selectedSource == source ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedSource == source ? .blue : .secondary)
                        }
                        .padding()
                        .background(
                            selectedSource == source
                                ? Color.blue.opacity(0.1)
                                : Color(.secondarySystemBackground)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(count < totalPairs)
                    .opacity(count < totalPairs ? 0.5 : 1.0)
                }
            }

            Text("\(totalPairs)쌍 매칭, 제한시간 \(Int(timeLimit))초")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                startGame()
            } label: {
                Text("시작")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(wordsForSource(selectedSource).count < totalPairs)

            if wordsForSource(selectedSource).count < totalPairs {
                Text("\(totalPairs)개 이상 필요합니다. (현재 \(wordsForSource(selectedSource).count)개)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Game Screen

    private var gameScreen: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text(String(format: "%.1f", timeRemaining))
                        .monospacedDigit()
                }
                .foregroundStyle(timeRemaining <= 5 ? .red : .primary)
                .font(.headline)

                Spacer()

                Text("✓\(correctCount)  ✗\(wrongCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(matchedPairs.count)/\(totalPairs)쌍")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(timeRemaining <= 5 ? Color.red : Color.purple)
                        .frame(width: geo.size.width * max(0, timeRemaining / timeLimit))
                        .animation(.linear(duration: 0.1), value: timeRemaining)
                }
            }
            .frame(height: 6)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(cards) { card in
                    cardButton(card)
                }
            }
        }
    }

    @ViewBuilder
    private func cardButton(_ card: MatchCard) -> some View {
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
                .frame(maxWidth: .infinity, minHeight: 110)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
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
                            isSelected ? Color.blue :
                            isMatched ? Color.green.opacity(0.5) :
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
        VStack(spacing: 16) {
            Image(systemName: success ? "trophy.fill" : "clock.badge.xmark.fill")
                .font(.system(size: 64))
                .foregroundStyle(success ? .yellow : .red)

            Text(success ? "클리어!" : "시간 초과!")
                .font(.largeTitle.bold())

            if success {
                Text(String(format: "%.1f초 만에 완료!", timeLimit - timeRemaining))
                    .font(.title2)
            }

            Text("정답 \(correctCount) · 오답 \(wrongCount)")
                .font(.subheadline)

            Text("다음 게임이 곧 시작됩니다...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                startGame()
            }
        }
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
                withAnimation {
                    wrongFlash = []
                }
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

    private func cardColor(
        isMatched: Bool,
        isCorrectFlash: Bool,
        isWrongFlash: Bool,
        isSelected: Bool,
        isEnglish: Bool
    ) -> Color {
        if isMatched { return Color.green.opacity(0.15) }
        if isCorrectFlash { return Color.green.opacity(0.4) }
        if isWrongFlash { return Color.red.opacity(0.4) }
        if isSelected { return Color.blue.opacity(0.3) }
        return isEnglish ? Color.blue.opacity(0.08) : Color.orange.opacity(0.08)
    }
}

// MARK: - Card Model

struct MatchCard: Identifiable {
    let id = UUID().uuidString
    let wordId: String
    let text: String
    let isEnglish: Bool
}
