import SwiftUI
import SwiftData

// MARK: - GameView (목업 구조 · hero-banner + game-grid)

enum GameDestination: Hashable {
    case quiz
    case flashcard
    case matching
    case recall
    case stats
}

struct GameView: View {
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var context
    @Environment(\.displayScale) private var displayScale
    @Query private var allWords: [Word]
    @AppStorage("learningMode") private var learningModeRaw: String = LearningMode.intensive.rawValue

    @State private var showClearAlert = false
    @State private var showResetWrongAlert = false
    @State private var showResetAllAlert = false
    @State private var showResetSRSLevelAlert = false
    @State private var showResetSRSDateAlert = false
    @State private var showRecalcDatesAlert = false
    @State private var showClearFavoritesAlert = false
    @State private var showClearHardAlert = false

    // 캐시된 값
    @State private var cachedDueCount: Int = 0
    @State private var cachedWrongWords: [Word] = []
    @State private var cachedHasAnyWrongCount: Bool = false
    @State private var cachedHasAnyLearning: Bool = false
    @State private var cachedFavoriteCount: Int = 0
    @State private var cachedHardCount: Int = 0

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
        cachedFavoriteCount = allWords.filter(\.isFavorite).count
        cachedHardCount = allWords.filter(\.isHard).count
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
                            .padding(.bottom, 14)

                        learningModeCard
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
                case .recall:    RecallView()
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
            .alert("SRS 레벨 초기화", isPresented: $showResetSRSLevelAlert) {
                Button("취소", role: .cancel) {}
                Button("초기화", role: .destructive) { resetAllSRSLevel() }
            } message: {
                Text("모든 단어의 SRS 레벨이 0으로 초기화됩니다.\n복습 일자와 정답·오답 기록은 유지됩니다.")
            }
            .alert("복습 일자 초기화", isPresented: $showResetSRSDateAlert) {
                Button("취소", role: .cancel) {}
                Button("초기화", role: .destructive) { resetAllSRSDate() }
            } message: {
                Text("모든 단어의 복습 일자가 지금으로 변경되어\n즉시 복습 대기열에 들어갑니다.\n레벨과 정답·오답 기록은 유지됩니다.")
            }
            .alert("복습 일자 재계산", isPresented: $showRecalcDatesAlert) {
                Button("취소", role: .cancel) {}
                Button("재계산", role: .destructive) { recalcAllReviewDates() }
            } message: {
                Text(recalcPreviewMessage)
            }
            .alert("즐겨찾기 전체 해제", isPresented: $showClearFavoritesAlert) {
                Button("취소", role: .cancel) {}
                Button("해제", role: .destructive) { clearAllFavorites() }
            } message: {
                Text("즐겨찾기된 단어 \(cachedFavoriteCount)개의 즐겨찾기가 모두 해제됩니다.")
            }
            .alert("어려움 전체 해제", isPresented: $showClearHardAlert) {
                Button("취소", role: .cancel) {}
                Button("해제", role: .destructive) { clearAllHard() }
            } message: {
                Text("🔥 어려움 표시된 단어 \(cachedHardCount)개의 표시가 모두 해제됩니다.")
            }
        }
    }

    /// 재계산 미리보기 - 영향받는 단어 수 계산
    private var recalcPreviewMessage: String {
        let preview = previewRecalc()
        var lines: [String] = []
        lines.append("현재 학습 모드: \(currentLearningMode.rawValue)")
        lines.append("")
        lines.append("재계산 후:")
        lines.append("• 즉시 복습 대기: \(preview.becomesDue)개")
        lines.append("• 일정 변경: \(preview.dateChanged)개")
        if preview.unchanged > 0 {
            lines.append("• 변경 없음(미학습): \(preview.unchanged)개")
        }
        return lines.joined(separator: "\n")
    }

    /// 재계산 미리보기 결과
    private struct RecalcPreview {
        var becomesDue: Int    // 재계산 후 즉시 복습 대기로 들어감
        var dateChanged: Int   // 학습한 단어 중 일정만 바뀜
        var unchanged: Int     // 미학습 단어 (lastReviewedAt == nil)
    }

    /// 실제로 적용하지 않고 미리 계산만
    private func previewRecalc() -> RecalcPreview {
        let intervals = SRSService.intervalsInDays
        let cal = Calendar.current
        let now = Date()
        var becomesDue = 0
        var dateChanged = 0
        var unchanged = 0

        for w in allWords {
            guard let lastReview = w.lastReviewedAt else {
                unchanged += 1
                continue
            }
            let level = min(max(w.srsLevel, 0), SRSService.maxLevel)
            let days = intervals[level]
            let newDate: Date
            if days <= 0 {
                newDate = now
            } else {
                newDate = cal.date(byAdding: .day, value: days, to: lastReview) ?? now
            }
            if newDate <= now {
                becomesDue += 1
            } else {
                dateChanged += 1
            }
        }
        return RecalcPreview(becomesDue: becomesDue, dateChanged: dateChanged, unchanged: unchanged)
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
            NavigationLink(value: GameDestination.recall) {
                gameCard(emoji: "🧠", name: "회상 카드", sub: "스스로 평가", meta: "능동")
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

    private var currentLearningMode: LearningMode {
        LearningMode(rawValue: learningModeRaw) ?? .intensive
    }

    /// 학습 모드 선택 카드 - 집중 모드 / 균형 모드 토글
    private var learningModeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("학습 모드")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .tracking(0.5)
                Spacer()
                Text(currentLearningMode.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }

            HStack(spacing: 8) {
                ForEach(LearningMode.allCases) { mode in
                    learningModeChip(mode)
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func learningModeChip(_ mode: LearningMode) -> some View {
        let isSelected = currentLearningMode == mode
        return Button {
            learningModeRaw = mode.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: mode.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Theme.ink : Theme.muted)
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                    }
                }
                Text(mode.description)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                Text(intervalSummary(for: mode))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.chipBg : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Theme.ink.opacity(0.3) : Theme.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// 모드별 간격 요약 텍스트
    private func intervalSummary(for mode: LearningMode) -> String {
        let days = mode.intervalsInDays.dropFirst()  // Lv.0 (즉시) 제외
        return days.map { "\($0)" }.joined(separator: "·") + "일"
    }

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

            adminRow(icon: "star.slash",
                     title: "즐겨찾기 전체 해제",
                     sub: cachedFavoriteCount == 0 ? "즐겨찾기 없음" : "\(cachedFavoriteCount)개 해제",
                     disabled: cachedFavoriteCount == 0) {
                showClearFavoritesAlert = true
            }

            divider

            adminRow(icon: "flame",
                     title: "어려움 전체 해제",
                     sub: cachedHardCount == 0 ? "어려움 표시 없음" : "\(cachedHardCount)개 해제",
                     disabled: cachedHardCount == 0) {
                showClearHardAlert = true
            }

            divider

            adminRow(icon: "minus.circle",
                     title: "오답 기록 전체 초기화",
                     sub: "오답 카운트 0으로",
                     disabled: !cachedHasAnyWrongCount) {
                showResetWrongAlert = true
            }

            divider

            adminRow(icon: "chart.bar",
                     title: "SRS 레벨 초기화",
                     sub: "모든 단어 Lv.0으로",
                     disabled: allWords.isEmpty) {
                showResetSRSLevelAlert = true
            }

            divider

            adminRow(icon: "calendar.badge.clock",
                     title: "복습 일자 초기화",
                     sub: "전체 단어 즉시 복습 대기",
                     disabled: allWords.isEmpty) {
                showResetSRSDateAlert = true
            }

            divider

            adminRow(icon: "arrow.counterclockwise",
                     title: "학습 기록 전체 초기화",
                     sub: "정답·오답·SRS 모두 리셋",
                     disabled: !cachedHasAnyLearning) {
                showResetAllAlert = true
            }

            divider

            adminRow(icon: "arrow.triangle.2.circlepath",
                     title: "복습 일자 재계산",
                     sub: "현재 학습 모드 간격으로 다시 계산",
                     disabled: allWords.isEmpty) {
                showRecalcDatesAlert = true
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

    private func clearAllFavorites() {
        for w in allWords where w.isFavorite { w.isFavorite = false }
        try? context.save()
        rebuildGameStats()
    }

    private func clearAllHard() {
        for w in allWords where w.isHard { w.isHard = false }
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

    /// 모든 단어의 SRS 레벨만 0으로 초기화
    /// 복습 일자와 정답/오답 카운트는 유지
    private func resetAllSRSLevel() {
        for w in allWords where w.srsLevel > 0 {
            w.srsLevel = 0
        }
        try? context.save()
        rebuildGameStats()
    }

    /// 모든 단어의 복습 일자만 지금으로 변경 → 즉시 복습 대기
    /// 레벨과 정답/오답 카운트는 유지
    private func resetAllSRSDate() {
        let now = Date()
        for w in allWords {
            w.nextReviewDate = now
        }
        try? context.save()
        rebuildGameStats()
    }

    /// 현재 학습 모드의 간격으로 모든 학습한 단어의 nextReviewDate를 재계산
    /// - 마지막 학습 시점(lastReviewedAt) 기준으로 간격 추가
    /// - lastReviewedAt이 없는 단어 (미학습)는 그대로 유지
    /// - 레벨 0이면 즉시 복습으로 설정
    private func recalcAllReviewDates() {
        let intervals = SRSService.intervalsInDays
        let cal = Calendar.current

        for w in allWords {
            // 미학습 단어는 그대로
            guard let lastReview = w.lastReviewedAt else { continue }

            let level = min(max(w.srsLevel, 0), SRSService.maxLevel)
            let days = intervals[level]

            if days <= 0 {
                // Lv.0 → 즉시 복습
                w.nextReviewDate = .now
            } else {
                w.nextReviewDate = cal.date(byAdding: .day, value: days, to: lastReview) ?? .now
            }
        }
        try? context.save()
        rebuildGameStats()
    }
}
