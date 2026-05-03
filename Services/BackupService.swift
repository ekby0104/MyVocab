import Foundation
import SwiftData

/// 단어 전체 데이터 백업/복원
/// JSON 형식으로 단어 + 즐겨찾기 + 메모 + 통계까지 보존
enum BackupService {

    /// 백업용 JSON 모델 (Word 모델과 분리되어 있어 모델 변경에 영향 안 받음)
    struct WordBackup: Codable {
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
        // v2부터 추가 (이전 버전과 호환되도록 옵셔널)
        var srsLevel: Int?
        var nextReviewDate: Date?
        // v3부터 추가
        var isHard: Bool?
    }

    struct BackupFile: Codable {
        var version: Int
        var exportedAt: Date
        var words: [WordBackup]
    }

    private static let currentVersion = 3

    // MARK: - Export

    /// 모든 단어를 JSON Data로 백업
    static func export(context: ModelContext) throws -> Data {
        let descriptor = FetchDescriptor<Word>(sortBy: [SortDescriptor(\.createdAt)])
        let allWords = try context.fetch(descriptor)

        let backups = allWords.map { w in
            WordBackup(
                english: w.english,
                pronunciation: w.pronunciation,
                partOfSpeech: w.partOfSpeech,
                meaning: w.meaning,
                example: w.example,
                exampleKo: w.exampleKo,
                memo: w.memo,
                createdAt: w.createdAt,
                lastReviewedAt: w.lastReviewedAt,
                correctCount: w.correctCount,
                wrongCount: w.wrongCount,
                isFavorite: w.isFavorite,
                isWrong: w.isWrong,
                srsLevel: w.srsLevel,
                nextReviewDate: w.nextReviewDate,
                isHard: w.isHard
            )
        }

        let file = BackupFile(version: currentVersion, exportedAt: .now, words: backups)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    /// 백업 파일을 임시 위치에 저장하고 URL 반환 (공유시트용)
    static func exportToFile(context: ModelContext) throws -> URL {
        let data = try export(context: context)
        let fileName = "MyVocab_backup_\(dateString()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url)
        return url
    }

    private static func dateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: .now)
    }

    // MARK: - Import

    struct RestoreResult {
        var restored: Int
        var skipped: Int
    }

    /// JSON Data를 읽어 단어 복원
    /// mergeMode: true면 기존 단어와 병합 (중복은 백업 데이터로 덮어씀)
    /// false면 기존 데이터 모두 삭제 후 복원
    static func restore(
        data: Data,
        context: ModelContext,
        replaceAll: Bool = false
    ) throws -> RestoreResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: data)

        // 기존 데이터 삭제 (replaceAll 모드)
        if replaceAll {
            let existing = (try? context.fetch(FetchDescriptor<Word>())) ?? []
            for w in existing { context.delete(w) }
        }

        // 중복 체크용 기존 단어 맵
        let existing = (try? context.fetch(FetchDescriptor<Word>())) ?? []
        var existingByKey: [String: Word] = [:]
        for w in existing {
            existingByKey[w.english.lowercased()] = w
        }

        var restored = 0
        let skipped = 0

        for backup in file.words {
            let key = backup.english.lowercased()
            if let existingWord = existingByKey[key] {
                // 기존 단어 → 백업 데이터로 메타데이터만 덮어쓰기
                // (단어/뜻은 유지, 즐겨찾기/메모/통계/SRS는 복원)
                existingWord.memo = backup.memo
                existingWord.isFavorite = backup.isFavorite
                existingWord.isWrong = backup.isWrong
                existingWord.correctCount = backup.correctCount
                existingWord.wrongCount = backup.wrongCount
                existingWord.lastReviewedAt = backup.lastReviewedAt
                // v2부터 추가된 필드 (구버전 백업이면 nil → 기본값 유지)
                if let srsLevel = backup.srsLevel {
                    existingWord.srsLevel = srsLevel
                }
                if backup.nextReviewDate != nil {
                    existingWord.nextReviewDate = backup.nextReviewDate
                }
                // v3부터 추가
                if let isHard = backup.isHard {
                    existingWord.isHard = isHard
                }
                restored += 1
            } else {
                // 새 단어 추가
                let word = Word(
                    english: backup.english,
                    pronunciation: backup.pronunciation,
                    partOfSpeech: backup.partOfSpeech,
                    meaning: backup.meaning,
                    example: backup.example,
                    exampleKo: backup.exampleKo,
                    memo: backup.memo,
                    createdAt: backup.createdAt,
                    lastReviewedAt: backup.lastReviewedAt,
                    correctCount: backup.correctCount,
                    wrongCount: backup.wrongCount,
                    isFavorite: backup.isFavorite,
                    isWrong: backup.isWrong,
                    isHard: backup.isHard ?? false,
                    srsLevel: backup.srsLevel ?? 0,
                    nextReviewDate: backup.nextReviewDate
                )
                context.insert(word)
                existingByKey[key] = word
                restored += 1
            }
        }

        try context.save()
        return RestoreResult(restored: restored, skipped: skipped)
    }
}
