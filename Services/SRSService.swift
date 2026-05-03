import Foundation

/// 학습 모드 - 시험 직전(집중) vs 평상시(균형)
enum LearningMode: String, CaseIterable, Identifiable {
    case intensive = "집중 모드"
    case balanced  = "균형 모드"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .intensive: return "시험 직전용 - 자주 복습"
        case .balanced:  return "평상시 학습 - 장기 기억"
        }
    }

    var icon: String {
        switch self {
        case .intensive: return "flame"
        case .balanced:  return "books.vertical"
        }
    }

    /// 레벨별 복습 간격 (일)
    var intervalsInDays: [Int] {
        switch self {
        case .intensive: return [0, 1, 2, 3, 4, 5, 6, 7]      // 1일 간격
        case .balanced:  return [0, 1, 3, 6, 12, 21, 35, 60]  // 점차 늘어남
        }
    }
}

/// Spaced Repetition System (Leitner box 방식 + 정답률 반영)
///
/// === 학습 모드별 레벨 간격 ===
///
/// 집중 모드 (시험 직전):
/// 0 → 즉시  1 → 1일  2 → 2일  3 → 3일  4 → 4일  5 → 5일  6 → 6일  7 → 7일
///
/// 균형 모드 (평상시):
/// 0 → 즉시  1 → 1일  2 → 3일  3 → 6일  4 → 12일  5 → 21일  6 → 35일  7 → 60일
///
/// === 레벨 변경 규칙 (모드 공통) ===
///
/// [정답 시]
/// - 정답률 ≥ 50% → 레벨 +1 후 정답률 캡 적용
/// - 정답률 < 50% → 레벨 그대로
///
/// [오답 시] - 차등 페널티
/// - 정답률 ≥ 70% → 레벨 -1
/// - 정답률 50~70% → 레벨 -2
/// - 정답률 30~50% → 레벨 -3
/// - 정답률 < 30% → 레벨 0
///
/// [정답률 캡] - 매번 적용
/// - 95%+ → 7,  90~95% → 6,  85~90% → 5,  80~85% → 4
/// - 70~80% → 3,  60~70% → 2,  50~60% → 1,  50% 미만 → 0
enum SRSService {
    static let maxLevel = 7

    /// 현재 학습 모드 (UserDefaults에 저장)
    static var currentMode: LearningMode {
        let raw = UserDefaults.standard.string(forKey: "learningMode") ?? LearningMode.intensive.rawValue
        return LearningMode(rawValue: raw) ?? .intensive
    }

    /// 현재 모드의 간격 배열
    static var intervalsInDays: [Int] {
        currentMode.intervalsInDays
    }

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

        // 정답률 캡 적용
        word.srsLevel = applyCap(word.srsLevel, accuracy: rate)

        // 다음 복습 일자
        word.nextReviewDate = nextDate(for: word.srsLevel, accuracy: rate)
    }

    /// 찍어서 맞춘 경우: 통계는 정답이지만 SRS 레벨은 올리지 않음
    static func guessed(_ word: Word) {
        word.correctCount += 1
        word.lastReviewedAt = .now
        word.isWrong = true
        // 레벨 그대로, 단 캡 적용
        let rate = accuracyRate(of: word)
        word.srsLevel = applyCap(word.srsLevel, accuracy: rate)
        // 즉시 복습 대기열로
        word.nextReviewDate = .now
    }

    /// 오답 시 - 정답률에 따른 차등 페널티
    static func wrong(_ word: Word) {
        // 통계 먼저 업데이트
        word.wrongCount += 1
        word.lastReviewedAt = .now
        word.isWrong = true

        // 정답률 기반 레벨 변경 (차등 페널티)
        let rate = accuracyRate(of: word)
        let penalty: Int
        if rate >= 0.7 {
            penalty = 1
        } else if rate >= 0.5 {
            penalty = 2
        } else if rate >= 0.3 {
            penalty = 3
        } else {
            // 30% 미만 → 완전 리셋
            word.srsLevel = 0
            word.nextReviewDate = Calendar.current.date(byAdding: .hour, value: 4, to: .now)
            return
        }
        word.srsLevel = max(word.srsLevel - penalty, 0)

        // 정답률 캡 적용
        word.srsLevel = applyCap(word.srsLevel, accuracy: rate)

        // 오답이면 4시간 후 복습 (정답률 무관)
        word.nextReviewDate = Calendar.current.date(byAdding: .hour, value: 4, to: .now)
    }

    // MARK: - Helpers

    /// 정답률에 따른 최대 레벨 캡
    private static func maxLevelByAccuracy(_ accuracy: Double) -> Int {
        switch accuracy {
        case 0.95...:     return 7
        case 0.90..<0.95: return 6
        case 0.85..<0.90: return 5
        case 0.80..<0.85: return 4
        case 0.70..<0.80: return 3
        case 0.60..<0.70: return 2
        case 0.50..<0.60: return 1
        default:          return 0
        }
    }

    /// 레벨에 정답률 캡 적용
    private static func applyCap(_ level: Int, accuracy: Double) -> Int {
        return min(level, maxLevelByAccuracy(accuracy))
    }

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
