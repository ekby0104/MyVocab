import Foundation

/// Spaced Repetition System (Leitner box 방식)
///
/// 레벨별 복습 간격:
/// 0 → 즉시 (방금 추가/오답)
/// 1 → 1일 후
/// 2 → 3일 후
/// 3 → 7일 후
/// 4 → 14일 후
/// 5 → 30일 후
/// 6 → 60일 후
/// 7 → 120일 후 (마스터)
enum SRSService {
    static let intervalsInDays: [Int] = [0, 1, 3, 7, 14, 30, 60, 120]
    static let maxLevel = 7

    /// 정답 시: 레벨 +1, 다음 복습 날짜 갱신
    static func correct(_ word: Word) {
        word.srsLevel = min(word.srsLevel + 1, maxLevel)
        word.nextReviewDate = nextDate(for: word.srsLevel)
        word.lastReviewedAt = .now
        word.correctCount += 1
        word.isWrong = false
    }

    /// 오답 시: 레벨 0으로 리셋, 즉시 복습 대상
    static func wrong(_ word: Word) {
        word.srsLevel = 0
        word.nextReviewDate = .now   // 즉시
        word.lastReviewedAt = .now
        word.wrongCount += 1
        word.isWrong = true
    }

    /// 레벨에 해당하는 다음 복습 날짜 계산
    private static func nextDate(for level: Int) -> Date {
        let days = intervalsInDays[min(level, maxLevel)]
        return Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
    }

    /// 오늘 복습할 단어 필터링 (nextReviewDate <= 지금)
    static func dueWords(from words: [Word]) -> [Word] {
        let now = Date()
        return words.filter { w in
            guard let next = w.nextReviewDate else {
                return false   // 한 번도 학습 안 한 건 due 아님 (별도 처리)
            }
            return next <= now
        }
    }

    /// 한 번도 학습 안 한 새 단어들
    static func newWords(from words: [Word]) -> [Word] {
        words.filter { $0.nextReviewDate == nil }
    }

    /// 레벨별 단어 수 분포
    static func levelDistribution(from words: [Word]) -> [Int: Int] {
        var dist: [Int: Int] = [:]
        for w in words {
            dist[w.srsLevel, default: 0] += 1
        }
        return dist
    }
}
