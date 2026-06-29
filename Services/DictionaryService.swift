import Foundation

// MARK: - Free Dictionary API 서비스
// 키/인증 불필요, 무제한
// https://dictionaryapi.dev

@MainActor
final class DictionaryService {
    static let shared = DictionaryService()

    enum DictError: LocalizedError {
        case notFound
        case rateLimited
        case httpError(Int)
        case invalidResponse
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .notFound:            return "이 단어를 사전에서 찾을 수 없습니다"
            case .rateLimited:         return "요청이 너무 많습니다. 잠시 후 다시 시도해주세요"
            case .httpError(let c):    return "HTTP \(c) 오류"
            case .invalidResponse:     return "응답을 해석할 수 없습니다"
            case .networkError(let e): return "네트워크 오류: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - 메모리 캐시

    private var cache: [String: DictionaryWordInfo] = [:]

    private init() {}

    // MARK: - 조회

    func lookup(_ word: String) async throws -> DictionaryWordInfo {
        let normalized = normalize(word)
        debugLog("[DictionaryService] lookup 호출: '\(word)' → normalized: '\(normalized)'")

        guard !normalized.isEmpty else {
            debugLog("[DictionaryService] normalized가 비어있음")
            throw DictError.notFound
        }

        if let cached = cache[normalized] {
            debugLog("[DictionaryService] 캐시 히트: '\(normalized)'")
            return cached
        }

        guard let encoded = normalized.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) else {
            debugLog("[DictionaryService] URL 인코딩 실패")
            throw DictError.invalidResponse
        }

        let urlString = "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)"
        debugLog("[DictionaryService] 요청 URL: \(urlString)")

        guard let url = URL(string: urlString) else {
            debugLog("[DictionaryService] URL 생성 실패")
            throw DictError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            debugLog("[DictionaryService] 네트워크 오류: \(error.localizedDescription)")
            throw DictError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            debugLog("[DictionaryService] HTTPURLResponse 변환 실패")
            throw DictError.invalidResponse
        }

        debugLog("[DictionaryService] HTTP \(http.statusCode), 응답 크기: \(data.count) bytes")

        switch http.statusCode {
        case 200:
            break
        case 404:
            debugLog("[DictionaryService] 404 - 단어를 찾을 수 없음")
            throw DictError.notFound
        case 429:
            debugLog("[DictionaryService] 429 - 요청 한도 초과")
            throw DictError.rateLimited
        default:
            if let body = String(data: data.prefix(500), encoding: .utf8) {
                debugLog("[DictionaryService] 오류 응답 본문: \(body)")
            }
            throw DictError.httpError(http.statusCode)
        }

        let entries: [DictionaryEntry]
        do {
            entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
        } catch {
            debugLog("[DictionaryService] JSON 디코딩 실패: \(error)")
            if let single = try? JSONDecoder().decode(NotFoundResponse.self, from: data) {
                debugLog("[DictionaryService] 단어 없음 응답: \(single.title ?? "")")
                throw DictError.notFound
            }
            throw DictError.invalidResponse
        }

        guard let info = entries.toWordInfo(word: normalized), !info.isEmpty else {
            debugLog("[DictionaryService] 응답은 받았으나 사용 가능한 정보 없음")
            throw DictError.notFound
        }

        cache[normalized] = info
        debugLog("[DictionaryService] 성공 + 캐시 저장: '\(normalized)' (그룹 \(info.lexicalGroups.count)개, 발음 \(info.pronunciations.count)개, 어원 \(info.origin == nil ? "없음" : "있음"))")
        return info
    }

    func invalidateCache(for word: String) {
        let key = normalize(word)
        cache.removeValue(forKey: key)
        debugLog("[DictionaryService] 캐시 무효화: '\(key)'")
    }

    func clearAllCache() {
        cache.removeAll()
        debugLog("[DictionaryService] 전체 캐시 클리어")
    }

    private func normalize(_ word: String) -> String {
        word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }
}

private struct NotFoundResponse: Decodable {
    let title: String?
    let message: String?
}
