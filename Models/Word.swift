import Foundation
import SwiftData

@Model
final class Word {
    @Attribute(.unique) var id: String
    var english: String
    var pronunciation: String
    var partOfSpeech: String
    var meaning: String
    var example: String
    var exampleKo: String
    var memo: String
    var createdAt: Date
    var lastReviewedAt: Date?
    var correctCount: Int
    var wrongCount: Int
    var isFavorite: Bool
    var isWrong: Bool

    // SRS (Spaced Repetition System)
    var srsLevel: Int            // 0~7, 높을수록 복습 간격 길어짐
    var nextReviewDate: Date?    // nil이면 아직 한 번도 학습 안 함

    init(
        id: String = UUID().uuidString,
        english: String,
        pronunciation: String = "",
        partOfSpeech: String = "",
        meaning: String = "",
        example: String = "",
        exampleKo: String = "",
        memo: String = "",
        createdAt: Date = .now,
        lastReviewedAt: Date? = nil,
        correctCount: Int = 0,
        wrongCount: Int = 0,
        isFavorite: Bool = false,
        isWrong: Bool = false,
        srsLevel: Int = 0,
        nextReviewDate: Date? = nil
    ) {
        self.id = id
        self.english = english
        self.pronunciation = pronunciation
        self.partOfSpeech = partOfSpeech
        self.meaning = meaning
        self.example = example
        self.exampleKo = exampleKo
        self.memo = memo
        self.createdAt = createdAt
        self.lastReviewedAt = lastReviewedAt
        self.correctCount = correctCount
        self.wrongCount = wrongCount
        self.isFavorite = isFavorite
        self.isWrong = isWrong
        self.srsLevel = srsLevel
        self.nextReviewDate = nextReviewDate
    }
}
