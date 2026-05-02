import Foundation

/// Spaced Repetition System (Leitner box 방식 + 정답률 반영)
///
/// 레벨별 복습 간격 (레벨 = 일수):
/// 0 → 즉시 (방금 추가/오답)
/// 1 → 1일 후
/// 2 → 2일 후
/// 3 → 3일 후
/// 4 → 4일 후
/// 5 → 5일 후
/// 6 → 6일 후
/// 7 → 7일 후 (마스터)
///
/// 레벨 변경 규칙 (정답률 반영):
/// - 정답 시 정답률 ≥ 50% → 레벨 +1
/// - 정답 시 정답률 < 50% → 레벨 그대로 (실력이 충분치 않으니 올리지 않음)
/// - 오답 시 정답률 ≥ 30% → 레벨 -1 (한 단계만 내림)
/// - 오답 시 정답률 < 30% → 레벨 0 (완전 리셋)
///
/// 다음 복습 일자 (정답률 반영):
/// - 정답률 ≥ 70% → 원래 간격 100%
/// - 정답률 50~70% → 원래 간격 75%
/// - 정답률 < 50% → 원래 간격 50%
/// - 오답 시 → 4시간 후 (정답률 무관)
enum SRSService {
    static let intervalsInDays: [Int] = [0, 1, 2, 3, 4, 5, 6, 7]
    static let maxLevel = 7

    // MARK: - Public API

    /// 정답 시
    static func correct(_ word: Word) {
        // 통계 먼저 업데이트
        word.correctCount += 1
        word.lastReviewedAt = .now
        word.isWrong = false

        // 정답률 기반 레벨 변경
        let rate = accuracyRate(of: word)
        if rate >= 0.5 {
            word.srsLevel = min(word.srsLevel + 1, maxLevel)
        }
        // 50% 미만이면 레벨 유지

        // 정답률 기반 다음 복습 일자
        word.nextReviewDate = nextDate(for: word.srsLevel, accuracy: rate)
    }

    /// 찍어서 맞춘 경우: 통계는 정답이지만 SRS 레벨은 올리지 않음
    static func guessed(_ word: Word) {
        word.correctCount += 1
        word.lastReviewedAt = .now
        word.isWrong = true
        // 레벨 그대로, 즉시 복습 대기열로
        word.nextReviewDate = .now
    }

    /// 오답 시
    static func wrong(_ word: Word) {
        // 통계 먼저 업데이트
        word.wrongCount += 1
        word.lastReviewedAt = .now
        word.isWrong = true

        // 정답률 기반 레벨 변경
        let rate = accuracyRate(of: word)
        if rate >= 0.3 {
            word.srsLevel = max(word.srsLevel - 1, 0)
        } else {
            word.srsLevel = 0
        }

        // 오답이면 4시간 후 복습 (정답률 무관)
        word.nextReviewDate = Calendar.current.date(byAdding: .hour, value: 4, to: .now)
    }

    // MARK: - Helpers

    /// 단어의 정답률 (0.0 ~ 1.0)
    /// 학습 기록이 없는 경우 1.0 (감점 없이 처음 간격대로 진행)
    private static func accuracyRate(of word: Word) -> Double {
        let total = word.correctCount + word.wrongCount
        guard total > 0 else { return 1.0 }
        return Double(word.correctCount) / Double(total)
    }

    /// 정답률에 따라 단축된 다음 복습 일자 계산
    private static func nextDate(for level: Int, accuracy: Double) -> Date {
        let baseDays = intervalsInDays[min(level, maxLevel)]
        // 레벨 0은 즉시
        guard baseDays > 0 else { return .now }

        // 정답률 따라 간격 비율 조정
        let multiplier: Double
        if accuracy >= 0.7 {
            multiplier = 1.0
        } else if accuracy >= 0.5 {
            multiplier = 0.75
        } else {
            multiplier = 0.5
        }

        let adjustedDays = max(1, Int(Double(baseDays) * multiplier))
        return Calendar.current.date(byAdding: .day, value: adjustedDays, to: .now) ?? .now
    }

    // MARK: - Queries

    static func dueWords(from words: [Word]) -> [Word] {
        let now = Date()
        return words.filter { w in
            guard let next = w.nextReviewDate else { return false }
            return next <= now
        }
    }

    static func newWords(from words: [Word]) -> [Word] {
        words.filter { $0.nextReviewDate == nil }
    }

    static func levelDistribution(from words: [Word]) -> [Int: Int] {
        var dist: [Int: Int] = [:]
        for w in words {
            dist[w.srsLevel, default: 0] += 1
        }
        return dist
    }
}
