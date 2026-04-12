import SwiftUI
import SwiftData

struct QuizView: View {
    enum Source {
        case all
        case favorites
        case wrongOnly
    }

    let source: Source
    init(source: Source = .all) { self.source = source }

    @Environment(\.modelContext) private var context
    @Query private var allWords: [Word]

    enum Mode: String, CaseIterable, Identifiable {
        case enToKo = "영→한"
        case koToEn = "한→영"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .enToKo
    @State private var started = false
    @State private var quizDeck: [Word] = []
    @State private var index = 0
    @State private var options: [Word] = []
    @State private var selectedId: String? = nil
    @State private var correctCount = 0
    @State private var wrongCount = 0

    // 문제 수
    @State private var quizCount: Int = 20
    @State private var customCountText: String = ""
    private let countOptions = [10, 20, 50, 100, 200, 500, 1000]

    var current: Word? {
        guard quizDeck.indices.contains(index) else { return nil }
        return quizDeck[index]
    }

    private var sourcePool: [Word] {
        switch source {
        case .all:        return allWords.filter { !$0.english.isEmpty && !$0.meaning.isEmpty }
        case .favorites:  return allWords.filter { $0.isFavorite && !$0.english.isEmpty && !$0.meaning.isEmpty }
        case .wrongOnly:  return allWords.filter { $0.isWrong && !$0.english.isEmpty && !$0.meaning.isEmpty }
        }
    }

    private var title: String {
        switch source {
        case .all:       return "퀴즈"
        case .favorites: return "즐겨찾기 퀴즈"
        case .wrongOnly: return "틀린 단어 복습"
        }
    }

    // 실제 출제될 문제 수 계산
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
                    Image(systemName: source == .wrongOnly ? "arrow.counterclockwise" : source == .favorites ? "star.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(source == .wrongOnly ? Color.orange : source == .favorites ? Color.yellow : Color.accentColor)
                    Text(title)
                }
                .font(.headline)
            }
        }
    }

    // MARK: - Start

    private var startScreen: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: source == .wrongOnly ? "arrow.counterclockwise.circle" : source == .favorites ? "star.circle" : "checkmark.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(source == .wrongOnly ? Color.orange : source == .favorites ? Color.yellow : Color.accentColor)

                Text(title)
                    .font(.title.bold())

                Picker("모드", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if source != .wrongOnly {
                    countSelector
                }

                switch source {
                case .wrongOnly:
                    Text("틀린 단어 \(sourcePool.count)개를 복습합니다.\n맞추면 자동으로 클리어됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                case .favorites:
                    Text("즐겨찾기 \(sourcePool.count)개 중 \(effectiveCount)개가 출제됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .all:
                    Text("전체 단어 \(sourcePool.count)개 중 \(effectiveCount)개가 출제됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    start()
                } label: {
                    Text("시작")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)

                if !canStart {
                    Text(source == .wrongOnly
                         ? "복습할 틀린 단어가 없습니다."
                         : "단어가 4개 이상 필요합니다.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
    }

    // 문제 수 선택 UI
    private var countSelector: some View {
        VStack(spacing: 10) {
            HStack {
                Text("문제 수")
                    .font(.subheadline)
                Spacer()
                Picker("프리셋", selection: $quizCount) {
                    ForEach(countOptions, id: \.self) { n in
                        Text("\(n)개").tag(n)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 8) {
                Text("직접 입력")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("예: 35", text: $customCountText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)
                    .onChange(of: customCountText) { _, newValue in
                        // 숫자만 추출
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue {
                            customCountText = filtered
                        }
                        if let n = Int(filtered), n > 0 {
                            quizCount = min(n, 1000)
                        }
                    }
                Text("개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("현재: \(quizCount)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var canStart: Bool {
        allWords.count >= 4 && !sourcePool.isEmpty
    }

    // MARK: - Quiz

    @ViewBuilder
    private func quizScreen(word: Word) -> some View {
        VStack(spacing: 20) {
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
                if mode == .enToKo, !word.pronunciation.isEmpty {
                    Text(word.pronunciation)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
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
            if source == .wrongOnly && correctCount > 0 {
                Text("\(correctCount)개 클리어됨")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
            Button("다시 시작") { started = false }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Logic

    private func start() {
        var src = sourcePool
        src.shuffle()
        quizDeck = source == .wrongOnly ? src : Array(src.prefix(quizCount))
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
    }

    private func answer(selected: Word, correct: Word) {
        selectedId = selected.id
        if selected.id == correct.id {
            correctCount += 1
            correct.correctCount += 1
            correct.isWrong = false
        } else {
            wrongCount += 1
            correct.wrongCount += 1
            correct.isWrong = true
        }
        correct.lastReviewedAt = .now
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
