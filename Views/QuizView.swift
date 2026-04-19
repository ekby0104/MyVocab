import SwiftUI
import SwiftData
import Combine

struct QuizView: View {
    @Environment(\.modelContext) private var context
    @Query private var allWords: [Word]

    // 시작 화면에서 선택
    @State private var selectedSource: SourceType = .all
    @State private var started = false

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

    // 반응 시간 측정
    @State private var questionShownAt: Date? = nil
    @State private var wasSlowResponse: Bool = false
    private let slowThreshold: TimeInterval = 5.0

    // 문제 수
    @State private var quizCount: Int = 20
    @State private var customCountText: String = ""
    private let countOptions = [10, 20, 50, 100, 200, 500, 1000]

    var current: Word? {
        guard quizDeck.indices.contains(index) else { return nil }
        return quizDeck[index]
    }

    private func wordsForSource(_ source: SourceType) -> [Word] {
        let base = allWords.filter { !$0.english.isEmpty && !$0.meaning.isEmpty }
        switch source {
        case .all:        return base
        case .favorites:  return base.filter(\.isFavorite)
        case .wrongOnly:  return base.filter(\.isWrong)
        case .dueToday:
            let now = Date()
            return base.filter { w in
                if let next = w.nextReviewDate { return next <= now }
                return true
            }
        }
    }

    private var sourcePool: [Word] { wordsForSource(selectedSource) }

    private var effectiveCount: Int {
        min(quizCount, sourcePool.count)
    }

    var body: some View {
        Group {
            if !started {
                startScreen
            } else if let word = current {
                quizScreen(word: word)
            } else {
                resultScreen
            }
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("퀴즈")
                }
                .font(.headline)
            }
        }
    }

    // MARK: - Start

    private var startScreen: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)

                Text("퀴즈")
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
                        .disabled(count < 4)
                        .opacity(count < 4 ? 0.5 : 1.0)
                    }
                }

                Picker("모드", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                countSelector

                Text("💡 5초 안에 답하지 않으면 오답으로 처리돼요")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    start()
                } label: {
                    Text("시작 (\(effectiveCount)문제)")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sourcePool.count < 4)

                if sourcePool.count < 4 {
                    Text("단어가 4개 이상 필요합니다.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            .padding()
        }
    }

    private var countSelector: some View {
        VStack(spacing: 10) {
            HStack {
                Text("문제 수").font(.subheadline)
                Spacer()
                Picker("프리셋", selection: $quizCount) {
                    ForEach(countOptions, id: \.self) { n in
                        Text("\(n)개").tag(n)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 8) {
                Text("직접 입력").font(.caption).foregroundStyle(.secondary)
                TextField("예: 35", text: $customCountText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)
                    .onChange(of: customCountText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { customCountText = filtered }
                        if let n = Int(filtered), n > 0 {
                            quizCount = min(n, 1000)
                        }
                    }
                Text("개").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("현재: \(quizCount)개").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Quiz

    @ViewBuilder
    private func quizScreen(word: Word) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(index + 1) / \(quizDeck.count)")
                Spacer()
                Text("✓ \(correctCount)  ✗ \(wrongCount)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(questionText(for: word))
                    .font(.system(size: mode == .koToEn ? 24 : 36, weight: .bold))
                    .multilineTextAlignment(.center)

                if mode == .enToKo {
                    Button {
                        SpeechService.shared.speak(word.english)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                }

                if mode == .enToKo, !word.pronunciation.isEmpty {
                    Text(word.pronunciation)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 10) {
                ForEach(options) { option in
                    Button {
                        guard selectedId == nil else { return }
                        answer(selected: option, correct: word)
                    } label: {
                        Text(answerText(for: option))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(backgroundColor(for: option, correct: word))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedId != nil {
                Button("다음") { advance() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear { startTimer() }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            checkSlowResponse()
        }
    }

    private func questionText(for word: Word) -> String {
        mode == .enToKo ? word.english : word.meaning
    }

    private func answerText(for word: Word) -> String {
        mode == .enToKo ? word.meaning : word.english
    }

    private func backgroundColor(for option: Word, correct: Word) -> Color {
        guard let sel = selectedId else { return Color(.tertiarySystemBackground) }
        if option.id == correct.id { return .green.opacity(0.3) }
        if option.id == sel { return .red.opacity(0.3) }
        return Color(.tertiarySystemBackground)
    }

    // MARK: - Result

    private var resultScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("완료!").font(.largeTitle.bold())
            Text("정답 \(correctCount) / \(correctCount + wrongCount)")
                .font(.title2)
            if selectedSource == .wrongOnly && correctCount > 0 {
                Text("\(correctCount)개 클리어됨")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
            Button("다시 시작") { started = false }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Timer

    private func startTimer() {
        questionShownAt = .now
        wasSlowResponse = false
    }

    private func checkSlowResponse() {
        guard selectedId == nil, let start = questionShownAt,
              let word = current else { return }
        if Date().timeIntervalSince(start) >= slowThreshold && !wasSlowResponse {
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
