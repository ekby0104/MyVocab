import SwiftUI
import SwiftData
import Combine

// MARK: - QuizView (목업 구조 · quiz-wrap / quiz-q / quiz-option)

struct QuizView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Query private var allWords: [Word]

    @State private var selectedSource: SourceType = .dueToday
    @State private var started = false
    /// 레벨별 학습 시 선택된 레벨들 (0~SRSService.maxLevel)
    @State private var selectedLevels: Set<Int> = []

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
    @AppStorage("quizGame.timeLimit") private var quizTimeSeconds: Int = 10
    private var slowThreshold: TimeInterval { TimeInterval(quizTimeSeconds) }

    @State private var elapsed: TimeInterval = 0

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

    // 캐싱: 시작 화면에서 반복 필터링 방지
    private var sourceCounts: [SourceType: Int] {
        let base = allWords.filter { !$0.english.isEmpty && !$0.meaning.isEmpty }
        let now = Date()
        return [
            .all: base.count,
            .favorites: base.filter(\.isFavorite).count,
            .wrongOnly: base.filter(\.isWrong).count,
            .hard: base.filter(\.isHard).count,
            .dueToday: base.filter { w in
                if let next = w.nextReviewDate { return next <= now }
                return true
            }.count,
            .byLevel: base.filter { selectedLevels.contains($0.srsLevel) }.count
        ]
    }

    private var sourcePool: [Word] { wordsForSource(selectedSource) }

    /// 소스별 최소 필요 단어 수
    /// - all: 6개 (6지선다 옵션 보장)
    /// - 그 외: 1개 (오답 선택지는 전체 단어에서 가져옴)
    private var minRequired: Int {
        selectedSource == .all ? 6 : 1
    }

    /// 6지선다 오답 선택지 만들 수 있는지 (전체 단어 5개 이상 필요)
    private var canMakeDistractors: Bool {
        let total = allWords.filter { !$0.english.isEmpty && !$0.meaning.isEmpty }.count
        return total >= 6
    }

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
                    Text("6지선다 퀴즈")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("10초 안에 답하지 않으면 오답")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }

                VStack(spacing: 8) {
                    ForEach(SourceType.allCases) { s in
                        sourceRow(s)
                    }
                    if selectedSource == .byLevel {
                        levelPicker
                    }
                }
                .padding(.horizontal, 20)

                modeSegmented.padding(.horizontal, 20)

                timeCard.padding(.horizontal, 20)

                HStack {
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
                    .disabled(sourcePool.count < minRequired || !canMakeDistractors)
                    .opacity((sourcePool.count < minRequired || !canMakeDistractors) ? 0.4 : 1)
                }
                .padding(.horizontal, 20)

                if !canMakeDistractors {
                    Text("전체 단어가 6개 이상 필요합니다")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.wrong)
                } else if sourcePool.count < minRequired {
                    Text(selectedSource == .dueToday
                         ? "오늘 학습할 단어가 없습니다"
                         : "단어가 \(minRequired)개 이상 필요합니다")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.wrong)
                }

                Spacer(minLength: 20)
            }
            .padding(.top, 4)
        }
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
                ForEach(0...SRSService.maxLevel, id: \.self) { lv in
                    levelChip(lv)
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

    private func levelChip(_ lv: Int) -> some View {
        let isSelected = selectedLevels.contains(lv)
        let count = allWords.filter {
            !$0.english.isEmpty && !$0.meaning.isEmpty && $0.srsLevel == lv
        }.count
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

    private func sourceRow(_ s: SourceType) -> some View {
        let count = sourceCounts[s] ?? 0
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
        .disabled(disabledForSource(s, count: count))
        .opacity(disabledForSource(s, count: count) ? 0.45 : 1)
    }

    private func disabledForSource(_ s: SourceType, count: Int) -> Bool {
        // byLevel은 항상 선택 가능 (선택 후 레벨 체크박스로 단어 추림)
        if s == .byLevel { return false }
        // dueToday, hard, wrongOnly, favorites는 1개 이상이면 가능 (오답 선택지는 전체에서)
        let required = (s == .dueToday || s == .hard || s == .wrongOnly || s == .favorites) ? 1 : 6
        return count < required
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

    /// 5초 단위로 5초 ~ 30초
    private static let timeOptions: [Int] = stride(from: 5, through: 30, by: 5).map { $0 }

    private var timeCard: some View {
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
                Picker("제한 시간", selection: $quizTimeSeconds) {
                    ForEach(Self.timeOptions, id: \.self) { sec in
                        Text("\(sec)초").tag(sec)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(quizTimeSeconds)초")
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

    // MARK: - Quiz running

    /// 가로 모드(landscape)인지 판별
    private var isLandscape: Bool { vSizeClass == .compact }

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

            if isLandscape {
                landscapeQuizBody(word: word)
            } else {
                portraitQuizBody(word: word)
            }
        }
        .padding(.top, 4)
        .onAppear { startTimer() }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            tick()
        }
    }

    /// 세로 모드 — 기존 레이아웃 (전체 ScrollView)
    @ViewBuilder
    private func portraitQuizBody(word: Word) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                questionCard(word: word)
                    .frame(minHeight: 160)
                    .padding(.horizontal, 20)

                optionsList(word: word, columns: 1)
                    .padding(.horizontal, 20)

                nextButton
                    .padding(.horizontal, 20)

                Spacer(minLength: 8)
            }
        }
        .scrollIndicators(.hidden)
    }

    /// 가로 모드 — 좌(문제) + 우(2열 3행 옵션)
    @ViewBuilder
    private func landscapeQuizBody(word: Word) -> some View {
        GeometryReader { geo in
            // 카드 최소 너비 280, 화면이 넓으면 35%까지 확장
            let cardWidth = max(280, min(geo.size.width * 0.35, 420))

            HStack(alignment: .top, spacing: 12) {
                // 왼쪽: 문제 카드 (고정 폭, 다음 버튼 높이만큼 빼기)
                questionCard(word: word)
                    .frame(width: cardWidth, height: geo.size.height - 56)

                // 오른쪽: 옵션 + 다음 버튼
                VStack(spacing: 8) {
                    landscapeOptionsGrid(word: word)
                        .frame(maxHeight: .infinity)

                    nextButton
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// 가로 모드 옵션 그리드 - 2열 3행, 모든 셀 동일 크기
    @ViewBuilder
    private func landscapeOptionsGrid(word: Word) -> some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let columns = 2
            let rows = 3
            let cellWidth = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: columns),
                spacing: spacing
            ) {
                ForEach(Array(options.enumerated()), id: \.element.id) { idx, option in
                    optionButton(idx: idx, option: option, word: word)
                        .frame(width: cellWidth, height: cellHeight)
                }
            }
        }
    }

    /// 문제 카드
    @ViewBuilder
    private func questionCard(word: Word) -> some View {
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

            // 우상단 버튼 영역
            HStack(spacing: 6) {
                // 정보 버튼: 답이 처리된 후에만 표시
                if selectedId != nil {
                    NavigationLink {
                        WordDetailView(word: word)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 28, height: 28)
                            .background(Theme.chipBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                // 발음 버튼: 영→한 모드일 때만
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(12)
        }
    }

    /// 옵션 리스트 (1열 또는 2열)
    @ViewBuilder
    private func optionsList(word: Word, columns: Int) -> some View {
        if columns == 1 {
            VStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.element.id) { idx, option in
                    optionButton(idx: idx, option: option, word: word)
                }
            }
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
                spacing: 8
            ) {
                ForEach(Array(options.enumerated()), id: \.element.id) { idx, option in
                    optionButton(idx: idx, option: option, word: word)
                }
            }
        }
    }

    /// 개별 옵션 버튼
    @ViewBuilder
    private func optionButton(idx: Int, option: Word, word: Word) -> some View {
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
                    .lineLimit(2)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(optionBg(for: option, correct: word))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(optionBorder(for: option, correct: word), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// 다음 문제 버튼 (답 미선택 시 "포기하기"로 동작)
    private var nextButton: some View {
        Button { advance() } label: {
            Text(selectedId == nil ? "포기하기" : "다음 문제")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedId == nil ? Theme.muted : Color(.systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selectedId == nil ? Theme.chipBg : Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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

            HStack(spacing: 8) {
                resultItem("\(correctCount)", "정답", Theme.correct)
                resultItem("\(wrongCount)", "오답", Theme.wrong)
                let total = correctCount + wrongCount
                resultItem(total > 0 ? "\(Int(Double(correctCount)/Double(total)*100))%" : "0%",
                           "정답률", Theme.ink)
            }
            .padding(.horizontal, 20)
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
            // save는 퀴즈 끝날 때 한 번만
        }
    }

    // MARK: - Logic

    private func start() {
        var src = sourcePool
        src.shuffle()
        quizDeck = src
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
        var distractors = Array(pool.shuffled().prefix(5))
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
        // save는 퀴즈 끝날 때 한 번만
    }

    private func advance() {
        // 답을 선택하지 않은 상태에서 "포기하기" 버튼을 눌렀다면
        // 오답 처리만 하고 진행은 멈춤 (사용자가 정답 확인 후 "다음 문제" 다시 눌러야 진행)
        if selectedId == nil, let word = current {
            // 정답을 선택된 것처럼 표시 (옵션에 ✓ 표시되도록)
            selectedId = word.id
            wrongCount += 1
            SRSService.wrong(word)
            return
        }

        if index + 1 >= quizDeck.count {
            try? context.save()   // 퀴즈 끝날 때 한 번만 저장
            quizDeck = []
        } else {
            index += 1
            rollOptions()
        }
    }
}
