import SwiftUI
import SwiftData

// MARK: - RecallView (자가 평가 회상 카드)
//
// 학습 흐름:
// 1) 영어 단어를 보여줌
// 2) 사용자가 머릿속으로 뜻을 떠올림
// 3) "정답 보기" 탭 → 한글 뜻 + 예문 공개
// 4) 자가 평가: 모름 / 헷갈림 / 알아
//    - 모름  : 오답 처리 (SRS wrong)
//    - 헷갈림: 약한 정답 (SRSService.guessed - 레벨 안 올림)
//    - 알아  : 정답 처리 (SRS correct)

struct RecallView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allWords: [Word]

    @State private var selectedSource: SourceType = .dueToday
    @State private var selectedLevels: Set<Int> = []
    @State private var started = false
    @State private var showAnswer = false

    @State private var deck: [Word] = []
    @State private var index: Int = 0
    @State private var correctCount = 0
    @State private var fuzzyCount = 0
    @State private var wrongCount = 0

    enum SourceType: String, CaseIterable, Identifiable {
        case all       = "전체 단어"
        case favorites = "즐겨찾기"
        case wrongOnly = "틀린 단어"
        case hard      = "어려움"
        case dueToday  = "오늘의 학습"
        case byLevel   = "레벨별"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all:       return "books.vertical"
            case .favorites: return "star"
            case .wrongOnly: return "arrow.counterclockwise"
            case .hard:      return "flame.fill"
            case .dueToday:  return "calendar"
            case .byLevel:   return "chart.bar"
            }
        }
    }

    private var current: Word? {
        guard deck.indices.contains(index) else { return nil }
        return deck[index]
    }

    /// 유효한 단어들 (한 번만 계산)
    private var validWords: [Word] {
        allWords.filter { !$0.english.isEmpty && !$0.meaning.isEmpty }
    }

    /// 레벨별 단어 수
    private var levelCounts: [Int: Int] {
        var counts: [Int: Int] = [:]
        for w in validWords {
            counts[w.srsLevel, default: 0] += 1
        }
        return counts
    }

    private func wordsForSource(_ source: SourceType) -> [Word] {
        let base = validWords
        switch source {
        case .all:       return base
        case .favorites: return base.filter(\.isFavorite)
        case .wrongOnly: return base.filter(\.isWrong)
        case .hard:      return base.filter(\.isHard)
        case .dueToday:
            let now = Date()
            return base.filter { w in
                if let next = w.nextReviewDate { return next <= now }
                return true
            }
        case .byLevel:
            return base.filter { selectedLevels.contains($0.srsLevel) }
        }
    }

    var body: some View {
        Group {
            if started {
                runningContent
            } else {
                startContent
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    // MARK: - Start Screen

    private var startContent: some View {
        VStack(spacing: 0) {
            topBar(title: "회상 카드", showClose: false)

            ScrollView {
                VStack(spacing: 14) {
                    // 헤로 영역
                    VStack(alignment: .leading, spacing: 6) {
                        Text("회상 카드")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("스스로 떠올리고 평가하는 능동적 학습")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    // 소스 선택
                    VStack(spacing: 8) {
                        ForEach(SourceType.allCases) { s in
                            sourceRow(s)
                        }
                        if selectedSource == .byLevel {
                            levelPicker
                        }
                    }
                    .padding(.horizontal, 20)

                    // 시작 버튼
                    Button { start() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 11))
                            Text("시작")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.ink)
                        .foregroundStyle(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(wordsForSource(selectedSource).isEmpty)
                    .opacity(wordsForSource(selectedSource).isEmpty ? 0.4 : 1)
                    .padding(.horizontal, 20)

                    if wordsForSource(selectedSource).isEmpty {
                        Text(selectedSource == .dueToday
                             ? "오늘 학습할 단어가 없습니다"
                             : "단어가 없습니다")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.wrong)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func sourceRow(_ s: SourceType) -> some View {
        let count = wordsForSource(s).count
        let isSelected = selectedSource == s
        let disabled = (s != .byLevel) && count == 0
        return Button {
            selectedSource = s
        } label: {
            HStack(spacing: 10) {
                Image(systemName: s.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 24, height: 24)
                    .background(Theme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(s.rawValue)
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
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    /// 레벨 체크박스 그룹 (byLevel 소스 선택 시 노출)
    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("레벨 선택")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .tracking(0.5)
                Spacer()
                Button {
                    if selectedLevels.count == SRSService.maxLevel + 1 {
                        selectedLevels = []
                    } else {
                        selectedLevels = Set(0...SRSService.maxLevel)
                    }
                } label: {
                    Text(selectedLevels.count == SRSService.maxLevel + 1 ? "전체 해제" : "전체 선택")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ], spacing: 6) {
                let counts = levelCounts
                ForEach(0...SRSService.maxLevel, id: \.self) { lv in
                    levelChip(lv, count: counts[lv] ?? 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func levelChip(_ lv: Int, count: Int) -> some View {
        let isSelected = selectedLevels.contains(lv)
        return Button {
            if isSelected {
                selectedLevels.remove(lv)
            } else {
                selectedLevels.insert(lv)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.muted)
                Text("Lv.\(lv)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.chipBg : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Theme.ink.opacity(0.3) : Theme.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Running Screen

    private var runningContent: some View {
        VStack(spacing: 0) {
            // 상단 바
            topBar(title: deck.isEmpty ? "완료" : "\(min(index + 1, deck.count)) / \(deck.count)",
                   showClose: true)

            if deck.isEmpty {
                // 결과 화면
                resultContent
            } else if let word = current {
                // 카드
                ScrollView {
                    VStack(spacing: 14) {
                        cardView(word: word)
                            .padding(.horizontal, 20)

                        if showAnswer {
                            evaluateButtons(word: word)
                                .padding(.horizontal, 20)
                                .transition(.opacity)
                        } else {
                            showAnswerButton
                                .padding(.horizontal, 20)
                                .transition(.opacity)
                        }
                    }
                    .padding(.vertical, 14)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// 단어 카드 - 영어(상단) + 정답 노출 시 한글/예문(하단)
    private func cardView(word: Word) -> some View {
        VStack(spacing: 14) {
            // 우상단 정보 / 발음 버튼
            HStack(alignment: .top) {
                if !word.partOfSpeech.isEmpty {
                    Text(word.partOfSpeech)
                        .font(.system(size: 11, weight: .medium))
                        .italic()
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if showAnswer {
                    NavigationLink {
                        WordDetailView(word: word)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 30, height: 30)
                            .background(Theme.chipBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                Button {
                    SpeechService.shared.speak(word.english)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 30, height: 30)
                        .background(Theme.chipBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }

            // 영어 단어
            VStack(spacing: 6) {
                Text(word.english)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                if !word.pronunciation.isEmpty {
                    Text(word.pronunciation)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)

            // 정답 영역
            if showAnswer {
                VStack(spacing: 8) {
                    Divider().overlay(Theme.line)
                    Text(word.meaning.isEmpty ? "-" : word.meaning)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                    if !word.example.isEmpty {
                        Text(word.example)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                        if !word.exampleKo.isEmpty {
                            Text(word.exampleKo)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var showAnswerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showAnswer = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "eye").font(.system(size: 12))
                Text("정답 보기")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.ink)
            .foregroundStyle(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// 자가 평가 버튼 - 모름 / 헷갈림 / 알아
    private func evaluateButtons(word: Word) -> some View {
        VStack(spacing: 8) {
            Text("알고 있었나요?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)

            HStack(spacing: 8) {
                evaluateButton(
                    emoji: "😢",
                    label: "모름",
                    sub: "다시 학습",
                    fg: Theme.wrong,
                    bg: Theme.wrong.opacity(0.10)
                ) {
                    SRSService.wrong(word)
                    wrongCount += 1
                    advance()
                }

                evaluateButton(
                    emoji: "🤔",
                    label: "헷갈림",
                    sub: "곧 다시",
                    fg: Color(red: 0.72, green: 0.53, blue: 0.10),
                    bg: Color(red: 1.0, green: 0.97, blue: 0.90)
                ) {
                    SRSService.guessed(word)
                    fuzzyCount += 1
                    advance()
                }

                evaluateButton(
                    emoji: "😊",
                    label: "알아",
                    sub: "다음에",
                    fg: Theme.correct,
                    bg: Theme.correct.opacity(0.10)
                ) {
                    SRSService.correct(word)
                    correctCount += 1
                    advance()
                }
            }
        }
    }

    private func evaluateButton(
        emoji: String,
        label: String,
        sub: String,
        fg: Color,
        bg: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emoji).font(.system(size: 24))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(fg)
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(bg)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(fg.opacity(0.3), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Result

    private var resultContent: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 4)

            Text("완료")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.ink)

            Text("총 \(correctCount + fuzzyCount + wrongCount)개 학습")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 8)

            HStack(spacing: 8) {
                resultItem("\(correctCount)", "알아", Theme.correct)
                resultItem("\(fuzzyCount)", "헷갈림", Color(red: 0.72, green: 0.53, blue: 0.10))
                resultItem("\(wrongCount)", "모름", Theme.wrong)
            }
            .padding(.horizontal, 20)

            Button { restart() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    Text("다시 시작")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.ink)
                .foregroundStyle(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()
        }
    }

    private func resultItem(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Top Bar

    private func topBar(title: String, showClose: Bool) -> some View {
        HStack {
            if showClose {
                Button { stopAndExit() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                        .background(Theme.chipBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                        .background(Theme.chipBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
            Spacer()
            // 우측 균형 맞춤용
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Logic

    private func start() {
        var src = wordsForSource(selectedSource)
        src.shuffle()
        deck = src
        index = 0
        correctCount = 0
        fuzzyCount = 0
        wrongCount = 0
        showAnswer = false
        started = true
    }

    private func restart() {
        start()
    }

    private func advance() {
        if index + 1 >= deck.count {
            try? context.save()
            deck = []
        } else {
            index += 1
            showAnswer = false
        }
    }

    private func stopAndExit() {
        try? context.save()
        deck = []
        started = false
        showAnswer = false
        dismiss()
    }
}
