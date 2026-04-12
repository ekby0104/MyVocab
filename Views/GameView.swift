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
    
    private var dueCount: Int {
        let now = Date()
        return allWords.filter { w in
            guard !w.english.isEmpty, !w.meaning.isEmpty else { return false }
            if let next = w.nextReviewDate { return next <= now }
            return true  // 새 단어
        }.count
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("학습 모드") {
                    NavigationLink {
                        FlashcardView()
                    } label: {
                        // 플래시카드
                        gameRow(
                            emoji: "🎴",
                            title: "플래시카드",
                            subtitle: "카드를 뒤집으며 암기",
                            color: .blue
                        )
                    }

                    NavigationLink {
                        QuizView(source: .all)
                    } label: {
                        // 퀴즈
                        gameRow(
                            emoji: "🎯",
                            title: "퀴즈",
                            subtitle: "4지선다 문제 풀기",
                            color: .green
                        )

                    }

                    NavigationLink {
                        QuizView(source: .favorites)
                    } label: {
                        // 즐겨찾기 퀴즈
                        gameRow(
                            emoji: "⭐️",
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
                        QuizView(source: .dueToday)
                    } label: {
                        gameRow(
                            emoji: "📅",
                            title: "오늘의 복습",
                            subtitle: dueCount == 0
                                ? "복습할 단어가 없어요"
                                : "\(dueCount)개 복습 대기 (SRS)",
                            color: .purple
                        )
                    }
                    .disabled(dueCount == 0)

                    NavigationLink {
                        QuizView(source: .wrongOnly)
                    } label: {
                        // 틀린 단어 복습
                        gameRow(
                            emoji: "🔄",
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
                
                Section("통계") {
                    NavigationLink {
                        StatsView()
                    } label: {
                        // 통계 (있다면)
                        gameRow(
                            emoji: "📊",
                            title: "학습 통계",
                            subtitle: "정답률 · 자주 틀리는 단어",
                            color: .indigo
                        )
                    }
                }
            }
            .navigationTitle("🎮 게임")
            .navigationBarTitleDisplayMode(.inline)
            .alert("전체 클리어", isPresented: $showClearAlert) {
                Button("취소", role: .cancel) {}
                Button("클리어", role: .destructive) { clearAllWrong() }
            } message: {
                Text("틀린 단어 \(wrongWords.count)개가 모두 클리어됩니다.")
            }
        }
    }

    private func gameRow(emoji: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: 48, height: 48)
                .background(color.opacity(0.18))
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
