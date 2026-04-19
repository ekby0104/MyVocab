import SwiftUI
import SwiftData

struct FlashcardView: View {
    @Environment(\.modelContext) private var context
    @Query private var allWords: [Word]

    // 시작 화면에서 선택
    @State private var selectedSource: SourceType = .all
    @State private var started = false

    // 카드 상태
    @State private var deck: [Word] = []
    @State private var index: Int = 0
    @State private var showBack: Bool = false
    @State private var autoTTS: Bool = false
    
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

    var current: Word? {
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
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !started {
                    startScreen
                } else if let word = current {
                    cardScreen(word: word)
                } else {
                    ContentUnavailableView(
                        "카드가 없습니다",
                        systemImage: "rectangle.on.rectangle",
                        description: Text("해당 조건에 맞는 단어가 없어요.")
                    )
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.on.rectangle.angled")
                            .foregroundStyle(Color.accentColor)
                        Text("플래시카드")
                    }
                    .font(.headline)
                }
            }
        }
    }

    // MARK: - Start Screen

    private var startScreen: some View {
        VStack(spacing: 24) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("플래시카드")
                .font(.title.bold())

            // 소스 선택
            VStack(spacing: 10) {
                ForEach(SourceType.allCases) { source in
                    let count = wordsForSource(source).count
                    Button {
                        selectedSource = source
                    } label: {
                        HStack {
                            Text(source.emoji)
                                .font(.title3)
                            Text(source.rawValue)
                                .font(.headline)
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
                    .disabled(count == 0)
                    .opacity(count == 0 ? 0.5 : 1.0)
                }
            }

            Button {
                startCards()
            } label: {
                Text("시작")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(wordsForSource(selectedSource).isEmpty)
        }
    }

    // MARK: - Card Screen

    private func cardScreen(word: Word) -> some View {
        VStack(spacing: 24) {
            Text("\(index + 1) / \(deck.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            cardView(for: word)
                .onTapGesture {
                    withAnimation(.spring) { showBack.toggle() }
                }

            HStack(spacing: 16) {
                Button {
                    prev()
                } label: {
                    Label("이전", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    next()
                } label: {
                    Label("다음", systemImage: "chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)

            Text("카드를 탭하면 뒤집힙니다")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        shuffleDeck()
                    } label: {
                        Label("섞기", systemImage: "shuffle")
                    }
                    Toggle("자동 발음", isOn: $autoTTS)
                    Divider()
                    Button {
                        started = false
                    } label: {
                        Label("다시 선택", systemImage: "arrow.uturn.backward")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Card View

    @ViewBuilder
    private func cardView(for word: Word) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(showBack ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                .shadow(radius: 4)

            VStack(spacing: 12) {
                if showBack {
                    if !word.partOfSpeech.isEmpty {
                        Text(word.partOfSpeech)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(word.meaning.isEmpty ? "-" : word.meaning)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if !word.example.isEmpty {
                        Divider().padding(.horizontal, 40)
                        Text(word.example)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if !word.exampleKo.isEmpty {
                            Text(word.exampleKo)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                } else {
                    Button {
                        SpeechService.shared.speak(word.english)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)

                    Text(word.english)
                        .font(.system(size: 44, weight: .bold))
                        .multilineTextAlignment(.center)
                    if !word.pronunciation.isEmpty {
                        Text(word.pronunciation)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .frame(height: 340)
        .animation(.spring, value: showBack)
    }

    // MARK: - Logic

    private func startCards() {
        shuffleDeck()
        started = true
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
        withAnimation {
            showBack = false
            index = (index + 1) % deck.count
        }
        if autoTTS, let w = current { SpeechService.shared.speak(w.english) }
    }

    private func prev() {
        guard !deck.isEmpty else { return }
        withAnimation {
            showBack = false
            index = (index - 1 + deck.count) % deck.count
        }
        if autoTTS, let w = current { SpeechService.shared.speak(w.english) }
    }
}
