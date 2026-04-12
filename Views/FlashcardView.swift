import SwiftUI
import SwiftData

struct FlashcardView: View {
    @Environment(\.modelContext) private var context
    @Query private var allWords: [Word]

    @State private var deck: [Word] = []
    @State private var index: Int = 0
    @State private var showBack: Bool = false
    @State private var favoritesOnly: Bool = false

    var current: Word? {
        guard deck.indices.contains(index) else { return nil }
        return deck[index]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let word = current {
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
                } else {
                    ContentUnavailableView(
                        "카드가 없습니다",
                        systemImage: "rectangle.on.rectangle",
                        description: Text("단어를 먼저 불러오세요.")
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            shuffleDeck()
                        } label: {
                            Label("섞기", systemImage: "shuffle")
                        }
                        Toggle("즐겨찾기만", isOn: $favoritesOnly)
                            .onChange(of: favoritesOnly) { _, _ in shuffleDeck() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                if deck.isEmpty { shuffleDeck() }
            }
        }
    }

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

    private func shuffleDeck() {
        var src = favoritesOnly ? allWords.filter(\.isFavorite) : allWords
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
        if let w = current { SpeechService.shared.speak(w.english) }  // 추가
    }

    private func prev() {
        guard !deck.isEmpty else { return }
        withAnimation {
            showBack = false
            index = (index - 1 + deck.count) % deck.count
        }
    }
}
