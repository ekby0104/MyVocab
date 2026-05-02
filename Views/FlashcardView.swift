import SwiftUI
import SwiftData

// MARK: - FlashcardView (목업 구조)

struct FlashcardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allWords: [Word]

    @State private var selectedSource: SourceType = .dueToday
    @State private var started = false

    @State private var deck: [Word] = []
    @State private var index: Int = 0
    @State private var showBack: Bool = false
    @AppStorage("flashcard.autoTTS") private var autoTTS: Bool = false
    /// 레벨별 학습 시 선택된 레벨들 (0~SRSService.maxLevel)
    @State private var selectedLevels: Set<Int> = []

    enum SourceType: String, CaseIterable, Identifiable {
        case all       = "전체 단어"
        case favorites = "즐겨찾기"
        case wrongOnly = "틀린 단어"
        case dueToday  = "오늘의 학습"
        case byLevel   = "레벨별"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all:       return "books.vertical"
            case .favorites: return "star"
            case .wrongOnly: return "arrow.counterclockwise"
            case .dueToday:  return "calendar"
            case .byLevel:   return "chart.bar"
            }
        }
    }

    private var current: Word? {
        guard deck.indices.contains(index) else { return nil }
        return deck[index]
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
        case .byLevel:
            return base.filter { selectedLevels.contains($0.srsLevel) }
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

    var body: some View {
        VStack(spacing: 0) {
            if !started {
                startTopBar
                startContent
            } else if current != nil {
                cardTopBar
                cardContent
            } else {
                startTopBar
                emptyState
            }
        }
        .background(Theme.surface)
        .navigationBarHidden(true)
    }

    // MARK: - Top bars

    private var startTopBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                iconChip(systemName: "chevron.left")
            }.buttonStyle(.plain)
            Spacer()
            Text("플래시카드")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var cardTopBar: some View {
        HStack {
            Button {
                started = false
            } label: {
                iconChip(systemName: "xmark")
            }.buttonStyle(.plain)
            Spacer()
            Text("\(min(index + 1, deck.count)) / \(deck.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
            Spacer()
            Button {
                shuffleDeck()
            } label: {
                iconChip(systemName: "shuffle")
            }.buttonStyle(.plain)
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

    // MARK: - Start content

    private var startContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 16)
                    Text("학습할 범위를 선택하세요")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 4)

                VStack(spacing: 8) {
                    ForEach(SourceType.allCases) { source in
                        let count = wordsForSource(source).count
                        Button {
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
                                Image(systemName: selectedSource == source ? "checkmark" : "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(selectedSource == source ? Theme.ink : Theme.line)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedSource == source ? Theme.ink : Theme.line,
                                            lineWidth: selectedSource == source ? 1.2 : 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(count == 0 && source != .byLevel)
                        .opacity(count == 0 && source != .byLevel ? 0.45 : 1)
                    }
                    if selectedSource == .byLevel {
                        levelPicker
                    }
                }
                .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    Button {
                        startCards()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 11))
                            Text("시작").font(.system(size: 14, weight: .semibold))
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
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                Spacer(minLength: 20)
            }
        }
    }

    // MARK: - Card content

    private var cardContent: some View {
        VStack(spacing: 12) {
            // progress
            HStack(spacing: 10) {
                Text(selectedSource.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.line).frame(height: 3)
                        RoundedRectangle(cornerRadius: 2).fill(Theme.ink)
                            .frame(width: geo.size.width * progressRatio, height: 3)
                    }
                }
                .frame(height: 3)
                if let word = current {
                    Text("Lv.\(word.srsLevel)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)

            // card
            if let word = current {
                flashCard(for: word)
                    .padding(.horizontal, 20)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showBack.toggle()
                        }
                    }
            }

            // auto read row
            HStack {
                Text("자동 발음")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Toggle("", isOn: $autoTTS)
                    .labelsHidden()
                    .tint(Theme.ink)
                    .scaleEffect(0.8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.chipBg)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)

            // controls
            HStack(spacing: 8) {
                Button { prev() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("이전")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .background(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 0.5))
                }.buttonStyle(.plain)

                Button { next() } label: {
                    HStack(spacing: 4) {
                        Text("다음")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .background(Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .padding(.top, 4)
    }

    private var progressRatio: CGFloat {
        guard deck.count > 0 else { return 0 }
        return CGFloat(index + 1) / CGFloat(deck.count)
    }

    // MARK: - Flash card

    @ViewBuilder
    private func flashCard(for word: Word) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 0.5))

            HStack(alignment: .top) {
                if !word.partOfSpeech.isEmpty {
                    Text(word.partOfSpeech)
                        .font(.system(size: 11, weight: .medium))
                        .italic()
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
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
            .padding(14)

            ZStack {
                // 뒷면 (뜻 / 예문)
                VStack(spacing: 10) {
                    if word.meaning.isEmpty {
                        Text("-")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    } else {
                        Text(word.meaning)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                    }
                    if !word.example.isEmpty {
                        Divider().overlay(Theme.line).padding(.horizontal, 30).padding(.vertical, 4)
                        Text(word.example)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                        if !word.exampleKo.isEmpty {
                            Text(word.exampleKo)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .opacity(showBack ? 1 : 0)

                // 앞면 (영어 단어)
                VStack(spacing: 10) {
                    Text(word.english)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .tracking(-0.5)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                    if !word.pronunciation.isEmpty {
                        Text(word.pronunciation)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    Text("탭하면 뜻이 보여요")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 4)
                }
                .opacity(showBack ? 0 : 1)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.muted)
            Text("카드가 없습니다").font(.system(size: 13, weight: .semibold))
            Text("해당 범위에 맞는 단어가 없어요.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    // MARK: - Logic

    private func startCards() {
        shuffleDeck()
        started = true
        if autoTTS, let w = current { SpeechService.shared.speak(w.english) }
    }

    private func shuffleDeck() {
        var src = wordsForSource(selectedSource)
        src.shuffle()
        deck = src
        index = 0
        showBack = false
    }

    private func next() {
        guard !deck.isEmpty else { return }
        showBack = false
        index = (index + 1) % deck.count
        if autoTTS, let w = current { SpeechService.shared.speak(w.english) }
    }

    private func prev() {
        guard !deck.isEmpty else { return }
        showBack = false
        index = (index - 1 + deck.count) % deck.count
        if autoTTS, let w = current { SpeechService.shared.speak(w.english) }
    }
}
