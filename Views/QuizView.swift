import SwiftUI
import SwiftData
import Combine

// MARK: - QuizView (목업 구조 · quiz-wrap / quiz-q / quiz-option)

struct QuizView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allWords: [Word]

    @State private var selectedSource: SourceType = .all
    @State private var started = false

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

    enum Mode: String, CaseIterable, Identifiable {
        case enToKo = "영→한"
        case koToEn = "한→영"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .enToKo
    @State private var quizDeck: [Word] = []
    @State private var index = 0
    @State private var options: [Word] = []
    @State private var selectedId: String? = nil
    @State private var correctCount = 0
    @State private var wrongCount = 0

    @State private var questionShownAt: Date? = nil
    @State private var wasSlowResponse: Bool = false
    private let slowThreshold: TimeInterval = 5.0
    @State private var elapsed: TimeInterval = 0

    @State private var quizCount: Int = 20
    @State private var customCountText: String = ""
    private let countOptions = [10, 20, 50, 100, 200, 500, 1000]

    private var current: Word? {
        guard quizDeck.indices.contains(index) else { return nil }
        return quizDeck[index]
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

    private var sourcePool: [Word] { wordsForSource(selectedSource) }
    private var effectiveCount: Int { min(quizCount, sourcePool.count) }

    var body: some View {
        VStack(spacing: 0) {
            if !started {
                startTopBar
                startContent
            } else if let word = current {
                runningTopBar
                quizContent(word: word)
            } else {
                runningTopBar
                resultContent
            }
        }
        .background(Theme.surface)
        .navigationBarHidden(true)
    }

    // MARK: - Top bars

    private var startTopBar: some View {
        HStack {
            Button { dismiss() } label: { iconChip(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Spacer()
            Text("퀴즈")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var runningTopBar: some View {
        HStack {
            Button { started = false } label: { iconChip(systemName: "xmark") }
                .buttonStyle(.plain)
            Spacer()
            Text(quizDeck.isEmpty
                 ? "완료"
                 : "Q \(min(index + 1, quizDeck.count)) / \(quizDeck.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
            Spacer()
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func iconChip(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(width: 32, height: 32)
            .background(Theme.chipBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Start

    private var startContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 12)
                    Text("4지선다 퀴즈")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("5초 안에 답하지 않으면 오답")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }

                VStack(spacing: 8) {
                    ForEach(SourceType.allCases) { s in
                        sourceRow(s)
                    }
                }
                .padding(.horizontal, 20)

                modeSegmented.padding(.horizontal, 20)

                countCard.padding(.horizontal, 20)

                HStack {
                    Button { start() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 11))
                            Text("시작 · \(effectiveCount)문제")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.ink)
                        .foregroundStyle(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(sourcePool.count < 4)
                    .opacity(sourcePool.count < 4 ? 0.4 : 1)
                }
                .padding(.horizontal, 20)

                if sourcePool.count < 4 {
                    Text("단어가 4개 이상 필요합니다")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.wrong)
                }

                Spacer(minLength: 20)
            }
            .padding(.top, 4)
        }
    }

    private func sourceRow(_ s: SourceType) -> some View {
        let count = wordsForSource(s).count
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
                Image(systemName: selectedSource == s ? "checkmark" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selectedSource == s ? Theme.ink : Theme.line)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedSource == s ? Theme.ink : Theme.line,
                            lineWidth: selectedSource == s ? 1.2 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(count < 4)
        .opacity(count < 4 ? 0.45 : 1)
    }

    private var modeSegmented: some View {
        HStack(spacing: 2) {
            ForEach(Mode.allCases) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { mode = m }
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 12, weight: mode == m ? .semibold : .medium))
                        .foregroundStyle(mode == m ? Theme.ink : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(mode == m ? Theme.surface : .clear)
                                .shadow(color: mode == m ? .black.opacity(0.06) : .clear,
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

    private var countCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("문제 수").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Menu {
                    ForEach(countOptions, id: \.self) { n in
                        Button("\(n)개") { quizCount = n; customCountText = "" }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(quizCount)개")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            HStack(spacing: 8) {
                Text("직접 입력").font(.system(size: 11)).foregroundStyle(Theme.muted)
                TextField("예: 35", text: $customCountText)
                    .font(.system(size: 12))
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 0.5))
                    .frame(maxWidth: 100)
                    .onChange(of: customCountText) { _, v in
                        let filtered = v.filter(\.isNumber)
                        if filtered != v { customCountText = filtered }
                        if let n = Int(filtered), n > 0 { quizCount = min(n, 1000) }
                    }
                Spacer()
            }
        }
        .padding(12)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 0.5))
    }

    // MARK: - Quiz running

    @ViewBuilder
    private func quizContent(word: Word) -> some View {
        VStack(spacing: 12) {
            // quiz-top (timer + score)
            HStack {
                Text(String(format: "⏱ %.1fs", elapsed))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("정답 \(correctCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.correct)
            }
            .padding(.horizontal, 20)

            // timer bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.line).frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(elapsed >= slowThreshold * 0.8 ? Theme.wrong : Theme.ink)
                        .frame(width: geo.size.width * min(1, CGFloat(elapsed / slowThreshold)), height: 3)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 20)

            // quiz-q card
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 0.5))

                VStack(spacing: 4) {
                    Text(mode == .enToKo ? "ENGLISH → KOREAN" : "KOREAN → ENGLISH")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .tracking(1.2)
                    Text(questionText(for: word))
                        .font(.system(size: mode == .koToEn ? 22 : 26, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .tracking(-0.3)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                    if mode == .enToKo, !word.pronunciation.isEmpty {
                        Text(word.pronunciation)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity)

                if mode == .enToKo {
                    Button { SpeechService.shared.speak(word.english) } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 28, height: 28)
                            .background(Theme.chipBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(12)
                }
            }
            .frame(minHeight: 160)
            .padding(.horizontal, 20)

            // options
            VStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.element.id) { idx, option in
                    Button {
                        guard selectedId == nil else { return }
                        answer(selected: option, correct: word)
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(numberFg(for: option, correct: word))
                                .frame(width: 22, height: 22)
                                .background(numberBg(for: option, correct: word))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(answerText(for: option))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(optionBg(for: option, correct: word))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(optionBorder(for: option, correct: word), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            if selectedId != nil {
                Button { advance() } label: {
                    Text("다음 문제")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }

            Spacer(minLength: 8)
        }
        .padding(.top, 4)
        .onAppear { startTimer() }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            tick()
        }
    }

    private func questionText(for word: Word) -> String {
        mode == .enToKo ? word.english : word.meaning
    }

    private func answerText(for word: Word) -> String {
        mode == .enToKo ? word.meaning : word.english
    }

    private func optionBg(for option: Word, correct: Word) -> Color {
        guard let sel = selectedId else { return Theme.surface }
        if option.id == correct.id { return Theme.correct.opacity(0.08) }
        if option.id == sel { return Theme.wrong.opacity(0.08) }
        return Theme.surface
    }

    private func optionBorder(for option: Word, correct: Word) -> Color {
        guard let sel = selectedId else { return Theme.line }
        if option.id == correct.id { return Theme.correct }
        if option.id == sel { return Theme.wrong }
        return Theme.line
    }

    private func numberBg(for option: Word, correct: Word) -> Color {
        guard let sel = selectedId else { return Theme.chipBg }
        if option.id == correct.id { return Theme.correct }
        if option.id == sel { return Theme.wrong }
        return Theme.chipBg
    }

    private func numberFg(for option: Word, correct: Word) -> Color {
        guard let sel = selectedId else { return Theme.ink }
        if option.id == correct.id || option.id == sel { return .white }
        return Theme.ink
    }

    // MARK: - Result

    private var resultContent: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.ink)
            Text("완료")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .tracking(-0.3)
            Text("정답 \(correctCount) / \(correctCount + wrongCount)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)

            HStack(spacing: 16) {
                resultItem("\(correctCount)", "정답", Theme.correct)
                resultItem("\(wrongCount)", "오답", Theme.wrong)
                let total = correctCount + wrongCount
                resultItem(total > 0 ? "\(Int(Double(correctCount)/Double(total)*100))%" : "0%",
                           "정답률", Theme.ink)
            }
            .padding(.top, 8)

            Button {
                started = false
            } label: {
                Text("다시 시작")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()
        }
    }

    private func resultItem(_ n: String, _ l: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(n)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
            Text(l)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .frame(minWidth: 56)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 0.5))
    }

    // MARK: - Timer

    private func startTimer() {
        questionShownAt = .now
        wasSlowResponse = false
        elapsed = 0
    }

    private func tick() {
        guard selectedId == nil, let start = questionShownAt else { return }
        elapsed = Date().timeIntervalSince(start)
        if elapsed >= slowThreshold && !wasSlowResponse, let word = current {
            wasSlowResponse = true
            selectedId = word.id
            wrongCount += 1
            SRSService.wrong(word)
            try? context.save()
        }
    }

    // MARK: - Logic

    private func start() {
        var src = sourcePool
        src.shuffle()
        quizDeck = selectedSource == .wrongOnly ? src : Array(src.prefix(quizCount))
        index = 0
        correctCount = 0
        wrongCount = 0
        selectedId = nil
        started = true
        rollOptions()
    }

    private func rollOptions() {
        guard let word = current else { return }
        let pool = allWords.filter { $0.id != word.id && !$0.english.isEmpty && !$0.meaning.isEmpty }
        var distractors = Array(pool.shuffled().prefix(3))
        distractors.append(word)
        distractors.shuffle()
        options = distractors
        selectedId = nil
        startTimer()
    }

    private func answer(selected: Word, correct: Word) {
        selectedId = selected.id
        if selected.id == correct.id {
            correctCount += 1
            SRSService.correct(correct)
        } else {
            wrongCount += 1
            SRSService.wrong(correct)
        }
        try? context.save()
    }

    private func advance() {
        if index + 1 >= quizDeck.count {
            quizDeck = []
        } else {
            index += 1
            rollOptions()
        }
    }
}
