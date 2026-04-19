import SwiftUI
import SwiftData

struct GameView: View {
    @Environment(\.modelContext) private var context
    @Query private var allWords: [Word]
    @State private var showClearAlert = false
    @State private var showResetAlert = false
    @State private var showResetWrongAlert = false
    @State private var showResetAllAlert = false

    private var wrongWords: [Word] {
        allWords.filter(\.isWrong)
    }

    private var dueCount: Int {
        let now = Date()
        return allWords.filter { w in
            guard !w.english.isEmpty, !w.meaning.isEmpty else { return false }
            if let next = w.nextReviewDate { return next <= now }
            return true
        }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section("학습 모드") {
                    NavigationLink {
                        FlashcardView()
                    } label: {
                        gameRow(
                            emoji: "🎴",
                            title: "플래시카드",
                            subtitle: "카드를 뒤집으며 암기",
                            color: .blue
                        )
                    }

                    NavigationLink {
                        QuizView()
                    } label: {
                        gameRow(
                            emoji: "🎯",
                            title: "퀴즈",
                            subtitle: "4지선다 문제 풀기",
                            color: .green
                        )
                    }

                    NavigationLink {
                        MatchingGameView()
                    } label: {
                        gameRow(
                            emoji: "🔀",
                            title: "단어 매칭",
                            subtitle: "영어-한글 짝 맞추기 (30초)",
                            color: .purple
                        )
                    }
                }
                
                Section("통계") {
                    NavigationLink {
                        StatsView()
                    } label: {
                        gameRow(
                            emoji: "📊",
                            title: "학습 통계",
                            subtitle: "정답률 · 자주 틀리는 단어",
                            color: .indigo
                        )
                    }
                }

                Section("관리") {
                    Button {
                        showClearAlert = true
                    } label: {
                        Label("틀린 단어 전체 해제", systemImage: "xmark.circle")
                    }
                    .tint(.orange)
                    .disabled(wrongWords.isEmpty)

                    Button(role: .destructive) {
                        showResetWrongAlert = true
                    } label: {
                        Label("오답 기록 전체 초기화", systemImage: "minus.circle")
                    }
                    .disabled(allWords.filter({ $0.wrongCount > 0 }).isEmpty)

                    Button(role: .destructive) {
                        showResetAllAlert = true
                    } label: {
                        Label("학습 기록 전체 초기화", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(allWords.filter({ $0.correctCount > 0 || $0.wrongCount > 0 }).isEmpty)
                }
            }
            .navigationTitle("🎮 게임")
            .navigationBarTitleDisplayMode(.inline)
            .alert("틀린 단어 전체 해제", isPresented: $showClearAlert) {
                Button("취소", role: .cancel) {}
                Button("해제", role: .destructive) { clearAllWrong() }
            } message: {
                Text("틀린 단어 \(wrongWords.count)개의 틀린 상태가 해제됩니다.\n오답 횟수는 유지됩니다.")
            }
            .alert("오답 기록 전체 초기화", isPresented: $showResetWrongAlert) {
                Button("취소", role: .cancel) {}
                Button("초기화", role: .destructive) { resetAllWrongCounts() }
            } message: {
                Text("모든 단어의 오답 횟수가 0으로 초기화됩니다.\n통계 및 TOP 10이 리셋됩니다.")
            }
            .alert("학습 기록 전체 초기화", isPresented: $showResetAllAlert) {
                Button("취소", role: .cancel) {}
                Button("초기화", role: .destructive) { resetAllLearning() }
            } message: {
                Text("모든 단어의 정답·오답·SRS·틀린 상태가\n전부 초기화됩니다. 되돌릴 수 없습니다.")
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

    private func resetAllWrongCounts() {
        for w in allWords where w.wrongCount > 0 {
            w.wrongCount = 0
        }
        try? context.save()
    }
    
    private func resetAllLearning() {
        for w in allWords where w.correctCount > 0 || w.wrongCount > 0 {
            w.correctCount = 0
            w.wrongCount = 0
            w.isWrong = false
            w.srsLevel = 0
            w.nextReviewDate = nil
            w.lastReviewedAt = nil
        }
        try? context.save()
    }
}
