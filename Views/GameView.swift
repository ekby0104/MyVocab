import SwiftUI
import SwiftData

struct GameView: View {
    @Environment(\.modelContext) private var context
    @Query private var allWords: [Word]
    @State private var showClearAlert = false

    private var wrongWords: [Word] {
        allWords.filter(\.isWrong)
    }

    private var favoriteWords: [Word] {
        allWords.filter(\.isFavorite)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("학습 모드") {
                    NavigationLink {
                        FlashcardView()
                    } label: {
                        gameRow(
                            icon: "rectangle.on.rectangle",
                            title: "플래시카드",
                            subtitle: "카드를 뒤집으며 암기",
                            color: .blue
                        )
                    }

                    NavigationLink {
                        QuizView(source: .all)
                    } label: {
                        gameRow(
                            icon: "checkmark.circle.fill",
                            title: "퀴즈",
                            subtitle: "전체 단어에서 4지선다",
                            color: .green
                        )
                    }

                    NavigationLink {
                        QuizView(source: .favorites)
                    } label: {
                        gameRow(
                            icon: "star.circle.fill",
                            title: "즐겨찾기 퀴즈",
                            subtitle: favoriteWords.isEmpty
                                ? "즐겨찾기 단어가 없습니다"
                                : "즐겨찾기 \(favoriteWords.count)개에서 출제",
                            color: .yellow
                        )
                    }
                    .disabled(favoriteWords.count < 4)
                }

                Section("복습") {
                    NavigationLink {
                        QuizView(source: .wrongOnly)
                    } label: {
                        gameRow(
                            icon: "arrow.counterclockwise",
                            title: "틀린 단어 복습",
                            subtitle: wrongWords.isEmpty
                                ? "틀린 단어가 없습니다"
                                : "\(wrongWords.count)개 복습 대기",
                            color: .orange
                        )
                    }
                    .disabled(wrongWords.isEmpty)

                    Button(role: .destructive) {
                        showClearAlert = true
                    } label: {
                        Label("틀린 단어 전체 클리어", systemImage: "trash")
                    }
                    .disabled(wrongWords.isEmpty)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "gamecontroller.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("게임")
                    }
                    .font(.headline)
                }
            }
            .alert("전체 클리어", isPresented: $showClearAlert) {
                Button("취소", role: .cancel) {}
                Button("클리어", role: .destructive) { clearAllWrong() }
            } message: {
                Text("틀린 단어 \(wrongWords.count)개가 모두 클리어됩니다.")
            }
        }
    }

    private func gameRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func clearAllWrong() {
        for w in wrongWords { w.isWrong = false }
        try? context.save()
    }
}
