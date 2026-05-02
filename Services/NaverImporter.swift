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
              let content = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any]
        else { return nil }

        // entry는 보통 content.entry 또는 content 자체일 수 있음
        let entry = (content["entry"] as? [String: Any]) ?? content

        // 1) english 추출 - 여러 위치 시도
        var english = ""
        if let members = entry["members"] as? [[String: Any]],
           let first = members.first {
            english = (first["entry_name"] as? String)
                ?? (first["entryName"] as? String)
                ?? (first["name"] as? String)
                ?? ""
        }
        if english.isEmpty {
            english = (entry["entry_name"] as? String)
                ?? (entry["entryName"] as? String)
                ?? (entry["name"] as? String)
                ?? ""
        }
        if english.isEmpty, let name = raw["name"] as? String {
            english = name.replacingOccurrences(of: "·", with: "")
        }
        english = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !english.isEmpty else { return nil }

        // 2) 발음 - 여러 위치 시도
        var pronunciation = ""
        if let members = entry["members"] as? [[String: Any]],
           let first = members.first,
           let prons = first["prons"] as? [[String: Any]],
           let firstPron = prons.first {
            pronunciation = (firstPron["pron_symbol"] as? String)
                ?? (firstPron["pronSymbol"] as? String)
                ?? (firstPron["symbol"] as? String)
                ?? (firstPron["phoneticSymbol"] as? String)
                ?? ""
        }
        if pronunciation.isEmpty,
           let prons = entry["prons"] as? [[String: Any]],
           let first = prons.first {
            pronunciation = (first["pron_symbol"] as? String)
                ?? (first["pronSymbol"] as? String)
                ?? ""
        }

        // 3) means 추출 - entry.means 또는 content.means
        var partNames: [String] = []
        var meaningTexts: [String] = []
        var example = ""
        var exampleKo = ""

        let meansArray: [[String: Any]] = (entry["means"] as? [[String: Any]])
            ?? (content["means"] as? [[String: Any]])
            ?? []

        for mean in meansArray {
            // 품사
            let part = (mean["part_name"] as? String)
                ?? (mean["partName"] as? String)
                ?? (mean["pos"] as? String)
                ?? ""
            if !part.isEmpty, !partNames.contains(part) {
                partNames.append(part)
            }

            // 뜻
            let m = (mean["show_mean"] as? String)
                ?? (mean["showMean"] as? String)
                ?? (mean["mean"] as? String)
                ?? (mean["definition"] as? String)
                ?? ""
            if !m.isEmpty {
                meaningTexts.append(m)
            }

            // 예문 (첫 번째 것만)
            if example.isEmpty {
                let examples = (mean["examples"] as? [[String: Any]]) ?? []
                if let firstEx = examples.first {
                    example = (firstEx["show_example"] as? String)
                        ?? (firstEx["showExample"] as? String)
                        ?? (firstEx["example"] as? String)
                        ?? (firstEx["sentence"] as? String)
                        ?? ""
                    let translations = (firstEx["translations"] as? [[String: Any]]) ?? []
                    if let firstTr = translations.first {
                        exampleKo = (firstTr["show_translation"] as? String)
                            ?? (firstTr["showTranslation"] as? String)
                            ?? (firstTr["translation"] as? String)
                            ?? ""
                    }
                }
            }
        }

        // 4) 만약 entry.means가 비어 있으면 members[0].means 시도 (네이버 응답 구조 변경 대응)
        if meaningTexts.isEmpty,
           let members = entry["members"] as? [[String: Any]],
           let first = members.first,
           let meansFromMember = first["means"] as? [[String: Any]] {
            for mean in meansFromMember {
                let part = (mean["part_name"] as? String)
                    ?? (mean["partName"] as? String)
                    ?? ""
                if !part.isEmpty, !partNames.contains(part) {
                    partNames.append(part)
                }
                let m = (mean["show_mean"] as? String)
                    ?? (mean["showMean"] as? String)
                    ?? (mean["mean"] as? String)
                    ?? (mean["value"] as? String)
                    ?? (mean["text"] as? String)
                    ?? ""
                if !m.isEmpty { meaningTexts.append(m) }

                if example.isEmpty,
                   let examples = mean["examples"] as? [[String: Any]],
                   let firstEx = examples.first {
                    example = (firstEx["show_example"] as? String)
                        ?? (firstEx["example"] as? String) ?? ""
                    if let translations = firstEx["translations"] as? [[String: Any]],
                       let firstTr = translations.first {
                        exampleKo = (firstTr["show_translation"] as? String)
                            ?? (firstTr["translation"] as? String) ?? ""
                    }
                }
            }
        }

        // 5) 최후 fallback: raw 데이터 자체에서 뜻 찾기 (네이버 응답에 따라 외부에 있을 수도 있음)
        if meaningTexts.isEmpty {
            let rawMean = (raw["meaning"] as? String)
                ?? (raw["mean"] as? String)
                ?? (raw["show_mean"] as? String)
                ?? (raw["showMean"] as? String)
                ?? (raw["definition"] as? String)
                ?? ""
            if !rawMean.isEmpty {
                meaningTexts.append(rawMean)
            }
        }

        // 6) 디버깅: 의미 파싱 실패 시 한 번 로그 (개발 빌드 한정)
        #if DEBUG
        if meaningTexts.isEmpty {
            print("[NaverImporter] '\(english)' 뜻 파싱 실패")
            print("  - raw keys: \(raw.keys.sorted())")
            print("  - content keys: \(content.keys.sorted())")
            if let entryDict = content["entry"] as? [String: Any] {
                print("  - entry keys: \(entryDict.keys.sorted())")
                if let members = entryDict["members"] as? [[String: Any]],
                   let first = members.first {
                    print("  - members[0] keys: \(first.keys.sorted())")
                    if let means = first["means"] as? [[String: Any]],
                       let m = means.first {
                        print("  - members[0].means[0] keys: \(m.keys.sorted())")
                    }
                }
            }
        }
        #endif

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

        // 명명된 엔티티
        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&nbsp;": " "
        ]
        for (k, v) in entities { out = out.replacingOccurrences(of: k, with: v) }

        // 숫자 형태 엔티티: &#1234; (10진수) 와 &#xAB; (16진수)
        out = decodeNumericEntities(out)

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// &#NNN; (10진수) 와 &#xNNN; (16진수) 형태의 HTML 엔티티 디코드
    private static func decodeNumericEntities(_ s: String) -> String {
        var result = s
        let pattern = "&#(x?[0-9a-fA-F]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }

        // 뒤에서부터 치환 (인덱스 깨짐 방지)
        let nsRange = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, range: nsRange).reversed()
        for match in matches {
            guard let entityRange = Range(match.range, in: result),
                  let codeRange = Range(match.range(at: 1), in: result)
            else { continue }
            let code = result[codeRange]
            let scalarValue: UInt32?
            if code.lowercased().hasPrefix("x") {
                scalarValue = UInt32(code.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(code, radix: 10)
            }
            if let v = scalarValue, let scalar = Unicode.Scalar(v) {
                result.replaceSubrange(entityRange, with: String(Character(scalar)))
            }
        }
        return result
    }
}

extension Notification.Name {
    static let vocabImported = Notification.Name("vocabImported")
}
