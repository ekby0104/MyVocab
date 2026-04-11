import Foundation
import SwiftData

enum NaverImporter {

    enum SkipReason: String {
        case duplicate = "중복"
        case emptyWord = "빈 단어"
        case parseFailed = "파싱 실패"
    }

    struct SkippedItem {
        var name: String
        var reason: SkipReason
    }

    struct ImportResult {
        var inserted: Int
        var skipped: Int
        var skippedItems: [SkippedItem]
        var errors: [String]

        var skippedCounts: [SkipReason: Int] {
            var dict: [SkipReason: Int] = [:]
            for item in skippedItems {
                dict[item.reason, default: 0] += 1
            }
            return dict
        }
    }

    static func importJSON(data: Data, context: ModelContext) throws -> ImportResult {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        var rawItems: [[String: Any]] = []

        if let dict = json as? [String: Any] {
            if let d = dict["data"] as? [String: Any],
               let items = d["m_items"] as? [[String: Any]] {
                rawItems = items
            } else if let items = dict["m_items"] as? [[String: Any]] {
                rawItems = items
            } else if let items = dict["items"] as? [[String: Any]] {
                rawItems = items
            }
        } else if let array = json as? [[String: Any]] {
            rawItems = array
        }

        guard !rawItems.isEmpty else {
            throw NSError(
                domain: "NaverImporter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "단어 항목을 찾을 수 없습니다. data.m_items 또는 배열 형태인지 확인하세요."]
            )
        }

        var inserted = 0
        var skippedItems: [SkippedItem] = []
        var errors: [String] = []

        let existing = (try? context.fetch(FetchDescriptor<Word>())) ?? []
        var existingKeys = Set(existing.map { $0.english.lowercased() })

        for raw in rawItems {
            let itemLabel = (raw["name"] as? String) ?? "(이름 없음)"

            if let word = parseNaverItem(raw) {
                let key = word.english.lowercased()
                if key.isEmpty {
                    skippedItems.append(.init(name: itemLabel, reason: .emptyWord))
                    continue
                }
                if existingKeys.contains(key) {
                    skippedItems.append(.init(name: word.english, reason: .duplicate))
                    continue
                }
                context.insert(word)
                existingKeys.insert(key)
                inserted += 1
            } else if let word = parseSimpleItem(raw) {
                let key = word.english.lowercased()
                if key.isEmpty {
                    skippedItems.append(.init(name: itemLabel, reason: .emptyWord))
                    continue
                }
                if existingKeys.contains(key) {
                    skippedItems.append(.init(name: word.english, reason: .duplicate))
                    continue
                }
                context.insert(word)
                existingKeys.insert(key)
                inserted += 1
            } else {
                skippedItems.append(.init(name: itemLabel, reason: .parseFailed))
            }
        }

        do { try context.save() }
        catch { errors.append("저장 실패: \(error.localizedDescription)") }

        return ImportResult(
            inserted: inserted,
            skipped: skippedItems.count,
            skippedItems: skippedItems,
            errors: errors
        )
    }

    // MARK: - Naver nested format

    private static func parseNaverItem(_ raw: [String: Any]) -> Word? {
        guard let contentStr = raw["content"] as? String,
              let contentData = contentStr.data(using: .utf8),
              let content = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let entry = content["entry"] as? [String: Any]
        else { return nil }

        var english = ""
        if let members = entry["members"] as? [[String: Any]],
           let first = members.first {
            english = (first["entry_name"] as? String) ?? ""
        }
        if english.isEmpty, let name = raw["name"] as? String {
            english = name.replacingOccurrences(of: "·", with: "")
        }
        english = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !english.isEmpty else { return nil }

        var pronunciation = ""
        if let members = entry["members"] as? [[String: Any]],
           let first = members.first,
           let prons = first["prons"] as? [[String: Any]],
           let firstPron = prons.first {
            pronunciation = (firstPron["pron_symbol"] as? String) ?? ""
        }

        var partNames: [String] = []
        var meaningTexts: [String] = []
        var example = ""
        var exampleKo = ""

        if let means = entry["means"] as? [[String: Any]] {
            for mean in means {
                if let part = mean["part_name"] as? String,
                   !part.isEmpty, !partNames.contains(part) {
                    partNames.append(part)
                }
                if let m = mean["show_mean"] as? String, !m.isEmpty {
                    meaningTexts.append(m)
                }
                if example.isEmpty,
                   let examples = mean["examples"] as? [[String: Any]],
                   let firstEx = examples.first {
                    example = (firstEx["show_example"] as? String) ?? ""
                    if let translations = firstEx["translations"] as? [[String: Any]],
                       let firstTr = translations.first {
                        exampleKo = (firstTr["show_translation"] as? String) ?? ""
                    }
                }
            }
        }

        return Word(
            english: cleanHTML(english),
            pronunciation: cleanHTML(pronunciation),
            partOfSpeech: cleanHTML(partNames.joined(separator: ", ")),
            meaning: cleanHTML(meaningTexts.joined(separator: "; ")),
            example: cleanHTML(example),
            exampleKo: cleanHTML(exampleKo)
        )
    }

    // MARK: - Simple flat format

    private static func parseSimpleItem(_ raw: [String: Any]) -> Word? {
        let english = pick(raw, ["english", "entry", "entryName", "word"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !english.isEmpty else { return nil }

        return Word(
            english: cleanHTML(english),
            pronunciation: cleanHTML(pick(raw, ["pronunciation", "pron", "phoneticSymbol", "phonetic"])),
            partOfSpeech: cleanHTML(pick(raw, ["partOfSpeech", "pos", "wordClass"])),
            meaning: cleanHTML(pick(raw, ["meaning", "mean", "definition", "desc"])),
            example: cleanHTML(pick(raw, ["example", "exampleEn", "exEn", "sentence"])),
            exampleKo: cleanHTML(pick(raw, ["exampleKo", "exKo", "translation", "meanExample"]))
        )
    }

    // MARK: - Helpers

    private static func pick(_ dict: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            if let s = dict[key] as? String, !s.isEmpty { return s }
            if let n = dict[key] as? NSNumber { return n.stringValue }
        }
        return ""
    }

    private static func cleanHTML(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var out = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&nbsp;": " "
        ]
        for (k, v) in entities { out = out.replacingOccurrences(of: k, with: v) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Notification.Name {
    static let vocabImported = Notification.Name("vocabImported")
}
