import SwiftUI
import SwiftData

// MARK: - GameView (목업 구조 · hero-banner + game-grid)

enum GameDestination: Hashable {
    case quiz
    case flashcard
    case matching
    case stats
}

struct GameView: View {
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var context
    @Environment(\.displayScale) private var displayScale
    @Query private var allWords: [Word]

    @State private var showClearAlert = false
    @State private var showResetWrongAlert = false
    @State private var showResetAllAlert = false

    // 캐시된 값
    @State private var cachedDueCount: Int = 0
    @State private var cachedWrongWords: [Word] = []
    @State private var cachedHasAnyWrongCount: Bool = false
    @State private var cachedHasAnyLearning: Bool = false

    init(path: Binding<NavigationPath>) {
        self._path = path
    }

    private var canReview: Bool { cachedDueCount > 0 }

    private func rebuildGameStats() {
        let now = Date()
        cachedDueCount = allWords.filter { w in
            guard !w.english.isEmpty, !w.meaning.isEmpty else { return false }
            if let next = w.nextReviewDate { return next <= now }
            return true
        }.count
        cachedWrongWords = allWords.filter(\.isWrong)
        cachedHasAnyWrongCount = allWords.contains { $0.wrongCount > 0 }
        cachedHasAnyLearning = allWords.contains { $0.correctCount > 0 || $0.wrongCount > 0 }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 0) {
                        heroBanner
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)

                        gameGrid
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)

                        adminCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .background(Theme.surface)
            .navigationBarHidden(true)
            .onAppear { rebuildGameStats() }
            .navigationDestination(for: GameDestination.self) { dest in
                switch dest {
                case .quiz:      QuizView()
                case .flashcard: FlashcardView()
                case .matching:  MatchingGameView()
                case .stats:     StatsView()
                }
            }
            .alert("틀린 단어 전체 해제", isPresented: $showClearAlert) {
                Button("취소", role: .cancel) {}
                Button("해제", role: .destructive) { clearAllWrong() }
            } message: {
                Text("틀린 단어 \(cachedWrongWords.count)개의 틀린 상태가 해제됩니다.\n오답 횟수는 유지됩니다.")
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

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Text("게임")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .tracking(-0.5)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Hero banner

    @ViewBuilder
    private var heroBanner: some View {
        if canReview {
            NavigationLink(value: GameDestination.quiz) {
                heroBannerCard
            }
            .buttonStyle(.plain)
        } else {
            heroBannerCard
        }
    }

    private var heroBannerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(canReview ? "오늘의 학습" : "오늘 복습할 단어 없음")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.5)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.14))
                .foregroundStyle(Color.white.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(canReview ? "\(cachedDueCount)단어 복습 준비됨" : "훌륭해요!")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .tracking(-0.2)
                .padding(.top, 10)

            Text(canReview
                 ? "SRS가 오늘 꼭 봐야 할 단어를 골라뒀어요."
                 : "새 단어를 추가하거나 플래시카드로 전체 복습해보세요.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.leading)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)

            if canReview {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("시작")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 12)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.067, green: 0.067, blue: 0.067))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Game grid

    private var gameGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            NavigationLink(value: GameDestination.flashcard) {
                gameCard(emoji: "🎴", name: "플래시카드", sub: "앞뒤 뒤집기 · 섞기", meta: "TTS")
            }.buttonStyle(.plain)
            NavigationLink(value: GameDestination.quiz) {
                gameCard(emoji: "🎯", name: "퀴즈", sub: "6지선다 · 영↔한", meta: "시간 선택")
            }.buttonStyle(.plain)
            NavigationLink(value: GameDestination.matching) {
                gameCard(emoji: "🔀", name: "매칭", sub: "4×4 카드 도전", meta: "30초")
            }.buttonStyle(.plain)
            NavigationLink(value: GameDestination.stats) {
                gameCard(emoji: "📊", name: "통계", sub: "정답률 · TOP 오답", meta: "Stats")
            }.buttonStyle(.plain)
        }
    }

    private func gameCard(emoji: String, name: String, sub: String, meta: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(meta)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Theme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Spacer(minLength: 10)

            Text(emoji)
                .font(.system(size: 22))

            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .tracking(-0.2)
                .padding(.top, 8)

            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Admin card

    private var adminCard: some View {
        VStack(spacing: 0) {
            Text("관리")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            adminRow(icon: "xmark.circle",
                     title: "틀린 단어 전체 해제",
                     sub: cachedWrongWords.isEmpty ? "틀린 단어 없음" : "\(cachedWrongWords.count)개 해제",
                     disabled: cachedWrongWords.isEmpty) {
                showClearAlert = true
            }

            divider

            adminRow(icon: "minus.circle",
                     title: "오답 기록 전체 초기화",
                     sub: "오답 카운트 0으로",
                     disabled: !cachedHasAnyWrongCount) {
                showResetWrongAlert = true
            }

            divider

            adminRow(icon: "arrow.counterclockwise",
                     title: "학습 기록 전체 초기화",
                     sub: "정답·오답·SRS 모두 리셋",
                     disabled: !cachedHasAnyLearning) {
                showResetAllAlert = true
            }
        }
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
    }

    private func adminRow(icon: String, title: String, sub: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 24, height: 24)
                    .background(Theme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.line)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Actions

    private func clearAllWrong() {
        for w in cachedWrongWords { w.isWrong = false }
        try? context.save()
        rebuildGameStats()
    }

    private func resetAllWrongCounts() {
        for w in allWords where w.wrongCount > 0 { w.wrongCount = 0 }
        try? context.save()
        rebuildGameStats()
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
        rebuildGameStats()
    }
}
