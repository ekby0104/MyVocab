import Foundation

// MARK: - MyMemory 번역 API 서비스 (EN→KO)
// 키/인증 불필요, 익명 일 5천 단어 (이메일 등록 시 5만)
// https://mymemory.translated.net/doc/spec.php

@MainActor
final class TranslationService {

    enum TransError: LocalizedError {
        case notFound
        case quotaExceeded
        case invalidResponse
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .notFound:            return "번역 결과를 찾을 수 없습니다"
            case .quotaExceeded:       return "오늘 번역 한도를 초과했습니다"
            case .invalidResponse:     return "응답을 해석할 수 없습니다"
            case .networkError(let e): return "네트워크 오류: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - 메모리 캐시
    private var cache: [String: String] = [:]

    func translate(_ word: String, from source: String = "en", to target: String = "ko") async throws -> String {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { throw TransError.notFound }

        if let cached = cache[normalized] {
            print("[TranslationService] 캐시 히트: '\(normalized)'")
            return cached
        }

        guard let q = normalized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw TransError.invalidResponse
        }

        let urlString = "https://api.mymemory.translated.net/get?q=\(q)&langpair=\(source)|\(target)"
        guard let url = URL(string: urlString) else { throw TransError.invalidResponse }
        print("[TranslationService] 요청 URL: \(urlString)")

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TransError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw TransError.invalidResponse }
        switch http.statusCode {
        case 200:  break
        case 429:  throw TransError.quotaExceeded
        default:   throw TransError.invalidResponse
        }

        guard let decoded = try? JSONDecoder().decode(MyMemoryResponse.self, from: data) else {
            throw TransError.invalidResponse
        }

        let text = decoded.responseData.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TransError.notFound }
        // 한도 초과 시 본문에 경고 문구가 들어옴
        if text.uppercased().contains("MYMEMORY WARNING") || text.uppercased().contains("QUOTA") {
            throw TransError.quotaExceeded
        }

        cache[normalized] = text
        print("[TranslationService] 성공 + 캐시 저장: '\(normalized)' → '\(text)'")
        return text
    }
}

private struct MyMemoryResponse: Decodable {
    let responseData: ResponseData
    struct ResponseData: Decodable {
        let translatedText: String
    }
}
