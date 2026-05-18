import Foundation

// MARK: - Free Dictionary API 응답 모델
// https://dictionaryapi.dev
// /api/v2/entries/en/{word}

struct DictionaryEntry: Decodable {
    let word: String?
    let phonetic: String?
    let phonetics: [DictPhonetic]?
    let meanings: [DictMeaning]?
    let origin: String?
    let sourceUrls: [String]?
    let license: DictLicense?
}

struct DictLicense: Decodable {
    let name: String?
    let url: String?
}

struct DictPhonetic: Decodable {
    let text: String?
    let audio: String?
}

struct DictMeaning: Decodable {
    let partOfSpeech: String?
    let definitions: [DictDefinition]?
    let synonyms: [String]?
    let antonyms: [String]?
}

struct DictDefinition: Decodable {
    let definition: String
    let example: String?
    let synonyms: [String]?
    let antonyms: [String]?
}

// MARK: - 화면 표시용 정리된 데이터

enum PronunciationDialect: String {
    case uk = "UK"
    case us = "US"
    case unknown = ""

    var flag: String {
        switch self {
        case .uk: return "🇬🇧"
        case .us: return "🇺🇸"
        case .unknown: return ""
        }
    }
}

struct PronunciationItem: Identifiable {
    let id = UUID()
    let dialect: PronunciationDialect
    let ipa: String?
    let audioURL: URL?
}

struct DictionaryWordInfo {
    let word: String
    let pronunciations: [PronunciationItem]   // UK/US/기타 (가능한 것만)
    let lexicalGroups: [LexicalGroup]
    let origin: String?
    let wiktionaryURL: URL?

    var isEmpty: Bool {
        pronunciations.isEmpty && lexicalGroups.isEmpty && origin == nil
    }
}

struct LexicalGroup: Identifiable {
    let id = UUID()
    let category: String
    let senses: [DisplaySense]
}

struct DisplaySense: Identifiable {
    let id = UUID()
    let definition: String
    let examples: [String]
    let synonyms: [String]
    let antonyms: [String]
}

// MARK: - 응답을 화면용으로 변환

extension Array where Element == DictionaryEntry {
    /// API는 [DictionaryEntry] 배열을 반환 (보통 한 개, 동음이의어는 여러 개)
    func toWordInfo(word: String) -> DictionaryWordInfo? {
        guard !isEmpty else { return nil }

        // MARK: 발음 (UK/US 분리)
        var ukItem: PronunciationItem?
        var usItem: PronunciationItem?
        var fallbackIPA: String?

        for entry in self {
            // entry.phonetic (단일 IPA - 보통 첫 번째 발음)
            if fallbackIPA == nil, let p = entry.phonetic, !p.isEmpty {
                fallbackIPA = p
            }

            // entry.phonetics 배열 (text + audio 쌍)
            for p in entry.phonetics ?? [] {
                let dialect = detectDialect(from: p.audio)
                let audioURL = makeAudioURL(from: p.audio)

                switch dialect {
                case .uk:
                    if ukItem == nil {
                        ukItem = PronunciationItem(dialect: .uk, ipa: p.text, audioURL: audioURL)
                    } else if ukItem?.audioURL == nil, audioURL != nil {
                        // 기존 항목에 오디오 없으면 보강
                        ukItem = PronunciationItem(
                            dialect: .uk,
                            ipa: ukItem?.ipa ?? p.text,
                            audioURL: audioURL
                        )
                    }
                case .us:
                    if usItem == nil {
                        usItem = PronunciationItem(dialect: .us, ipa: p.text, audioURL: audioURL)
                    } else if usItem?.audioURL == nil, audioURL != nil {
                        usItem = PronunciationItem(
                            dialect: .us,
                            ipa: usItem?.ipa ?? p.text,
                            audioURL: audioURL
                        )
                    }
                case .unknown:
                    // 방언 미상이면 fallbackIPA 보강용
                    if fallbackIPA == nil, let t = p.text, !t.isEmpty {
                        fallbackIPA = t
                    }
                }
            }
        }

        var pronunciations: [PronunciationItem] = []
        if let uk = ukItem { pronunciations.append(uk) }
        if let us = usItem { pronunciations.append(us) }

        // UK/US 둘 다 없으면 fallback IPA를 unknown으로
        if pronunciations.isEmpty, let ipa = fallbackIPA {
            pronunciations.append(PronunciationItem(
                dialect: .unknown,
                ipa: ipa,
                audioURL: nil
            ))
        }

        // MARK: 품사별 정의 정리
        var groupedByPOS: [String: [DisplaySense]] = [:]
        var posOrder: [String] = []

        for entry in self {
            guard let meanings = entry.meanings else { continue }
            for meaning in meanings {
                let pos = meaning.partOfSpeech ?? "etc"
                var senses: [DisplaySense] = []

                let topSyns = meaning.synonyms ?? []
                let topAnts = meaning.antonyms ?? []

                for def in meaning.definitions ?? [] {
                    let mergedSyns = (def.synonyms ?? []) + topSyns
                    let mergedAnts = (def.antonyms ?? []) + topAnts

                    // 중복 제거 + 순서 유지
                    var uniqueSyns: [String] = []
                    for s in mergedSyns where !uniqueSyns.contains(s) { uniqueSyns.append(s) }

                    var uniqueAnts: [String] = []
                    for a in mergedAnts where !uniqueAnts.contains(a) { uniqueAnts.append(a) }

                    senses.append(DisplaySense(
                        definition: def.definition,
                        examples: [def.example].compactMap { $0 },
                        synonyms: uniqueSyns,
                        antonyms: uniqueAnts
                    ))
                }

                if !senses.isEmpty {
                    if groupedByPOS[pos] == nil {
                        groupedByPOS[pos] = []
                        posOrder.append(pos)
                    }
                    groupedByPOS[pos]?.append(contentsOf: senses)
                }
            }
        }

        let groups = posOrder.map { pos in
            LexicalGroup(category: pos, senses: groupedByPOS[pos] ?? [])
        }

        // MARK: 어원 (첫 entry에서)
        let origin = self.compactMap { $0.origin }.first(where: { !$0.isEmpty })

        // MARK: Wiktionary 링크
        let urlStr = self
            .compactMap { $0.sourceUrls }
            .flatMap { $0 }
            .first(where: { $0.contains("wiktionary") || !$0.isEmpty })
        let wiktionaryURL = urlStr.flatMap { URL(string: $0) }

        return DictionaryWordInfo(
            word: word,
            pronunciations: pronunciations,
            lexicalGroups: groups,
            origin: origin,
            wiktionaryURL: wiktionaryURL
        )
    }

    // MARK: - 헬퍼

    /// 오디오 URL에서 방언 추출
    private func detectDialect(from audio: String?) -> PronunciationDialect {
        guard let audio, !audio.isEmpty else { return .unknown }
        let lower = audio.lowercased()
        if lower.contains("_gb_") || lower.contains("_uk_") || lower.contains("-uk.") {
            return .uk
        }
        if lower.contains("_us_") || lower.contains("-us.") {
            return .us
        }
        return .unknown
    }

    /// protocol-relative URL ("//ssl.gstatic.com/...") 처리
    private func makeAudioURL(from raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        let full = raw.hasPrefix("//") ? "https:\(raw)" : raw
        return URL(string: full)
    }
}
