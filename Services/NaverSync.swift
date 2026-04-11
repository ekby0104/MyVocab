import Foundation
import WebKit

// MARK: - Wordbook (동적)

struct Wordbook: Codable, Identifiable, Hashable {
    let id: String   // wbId (빈 문자열이면 "전체")
    let name: String

    static let all = Wordbook(id: "", name: "전체")
}

// MARK: - Naver Sync Service

enum NaverSync {
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func wordsURL(for wordbook: Wordbook) -> URL {
        URL(string: "https://learn.dict.naver.com/gateway-api/enkodict/mywordbook/word/list/search?wbId=\(wordbook.id)&qt=0&st=0&page=1&page_size=10000&domain=naver")!
    }

    static let wordbookListURL = URL(string: "https://learn.dict.naver.com/gateway-api/enkodict/mywordbook/wordbook/list.dict?page=1&page_size=100&st=0&isRevision=true&domain=naver")!

    enum SyncError: LocalizedError {
        case notLoggedIn
        case sessionExpired
        case httpError(Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:      return "로그인이 필요합니다"
            case .sessionExpired:   return "세션이 만료되었습니다. 다시 로그인하세요"
            case .httpError(let c): return "HTTP \(c) 오류"
            case .invalidResponse:  return "응답 형식이 올바르지 않습니다"
            }
        }
    }

    // MARK: - 단어장 목록 가져오기

    /// WebView 쿠키로 단어장 목록 가져오기 (로그인 직후)
    static func fetchWordbookListWithWebView(webView: WKWebView) async throws -> [Wordbook] {
        let cookies = try await extractAndSaveCookies(from: webView)
        return try await fetchWordbookListWithCookies(cookies)
    }

    /// 저장된 쿠키로 단어장 목록 가져오기
    static func refreshWordbookList() async throws -> [Wordbook] {
        let cookies = try loadValidCookies()
        return try await fetchWordbookListWithCookies(cookies)
    }

    private static func fetchWordbookListWithCookies(_ cookies: [HTTPCookie]) async throws -> [Wordbook] {
        let request = makeRequest(url: wordbookListURL, cookies: cookies)
        let (data, response) = try await URLSession.shared.data(for: request)

        try checkResponse(data: data, response: response)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.invalidResponse
        }

        var items: [[String: Any]] = []
        if let d = json["data"] as? [String: Any], let arr = d["m_items"] as? [[String: Any]] {
            items = arr
        } else if let arr = json["m_items"] as? [[String: Any]] {
            items = arr
        } else if let d = json["data"] as? [String: Any], let arr = d["items"] as? [[String: Any]] {
            items = arr
        }

        // "전체"를 맨 위에 고정, 그 뒤에 실제 단어장들
        var list: [Wordbook] = [.all]
        var seen = Set<String>([""])

        for item in items {
            let id = (item["id"] as? String)
                ?? (item["wbId"] as? String)
                ?? (item["wordbookId"] as? String)
                ?? ""
            let name = (item["name"] as? String)
                ?? (item["title"] as? String)
                ?? (item["wordbookName"] as? String)
                ?? "단어장"
            let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedId.isEmpty, !seen.contains(trimmedId) else { continue }
            seen.insert(trimmedId)
            list.append(Wordbook(id: trimmedId, name: name))
        }

        WordbookStorage.save(list)
        return list
    }

    // MARK: - 단어 데이터 가져오기

    /// WebView 쿠키로 동기화 (로그인 직후)
    static func fetchWithWebViewCookies(
        webView: WKWebView,
        wordbook: Wordbook
    ) async throws -> Data {
        let cookies = try await extractAndSaveCookies(from: webView)
        return try await fetchWithCookies(cookies, url: wordsURL(for: wordbook))
    }

    /// 저장된 쿠키로 바로 동기화
    static func quickSync(wordbook: Wordbook) async throws -> Data {
        let cookies = try loadValidCookies()
        return try await fetchWithCookies(cookies, url: wordsURL(for: wordbook))
    }

    // MARK: - Private helpers

    private static func extractAndSaveCookies(from webView: WKWebView) async throws -> [HTTPCookie] {
        let dataStore = webView.configuration.websiteDataStore
        let cookies = await dataStore.httpCookieStore.allCookies()
        let naverCookies = cookies.filter { $0.domain.contains("naver.com") }

        guard naverCookies.contains(where: { $0.name == "NID_SES" || $0.name == "NID_AUT" }) else {
            throw SyncError.notLoggedIn
        }

        CookieStorage.save(naverCookies)
        return naverCookies
    }

    private static func loadValidCookies() throws -> [HTTPCookie] {
        let cookies = CookieStorage.load()
        guard !cookies.isEmpty,
              cookies.contains(where: { $0.name == "NID_SES" || $0.name == "NID_AUT" })
        else {
            throw SyncError.notLoggedIn
        }
        return cookies
    }

    private static func makeRequest(url: URL, cookies: [HTTPCookie]) -> URLRequest {
        var request = URLRequest(url: url)
        let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("ko-KR,ko;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://learn.dict.naver.com/dict/mywordbook", forHTTPHeaderField: "Referer")
        request.setValue("https://learn.dict.naver.com", forHTTPHeaderField: "Origin")
        return request
    }

    private static func checkResponse(data: Data, response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SyncError.httpError(http.statusCode)
        }
        if let text = String(data: data, encoding: .utf8) {
            if text.contains("\"rtn_cd\":920") || text.contains("no authority") {
                CookieStorage.clear()
                throw SyncError.sessionExpired
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
                CookieStorage.clear()
                throw SyncError.sessionExpired
            }
        }
    }

    private static func fetchWithCookies(_ cookies: [HTTPCookie], url: URL) async throws -> Data {
        let request = makeRequest(url: url, cookies: cookies)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(data: data, response: response)
        UserDefaults.standard.set(Date(), forKey: "lastSyncDate")
        return data
    }
}

// MARK: - Wordbook Storage

enum WordbookStorage {
    private static let key = "wordbookList.v1"

    static func save(_ list: [Wordbook]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [Wordbook] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Wordbook].self, from: data)
        else { return [.all] }   // 저장된 게 없으면 "전체"만
        return list.isEmpty ? [.all] : list
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Cookie Storage

enum CookieStorage {
    private static let key = "naverCookies.v1"

    struct SavedCookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let expires: Date?
        let isSecure: Bool

        init(from cookie: HTTPCookie) {
            self.name = cookie.name
            self.value = cookie.value
            self.domain = cookie.domain
            self.path = cookie.path
            self.expires = cookie.expiresDate
            self.isSecure = cookie.isSecure
        }

        func toHTTPCookie() -> HTTPCookie? {
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path
            ]
            if let e = expires { props[.expires] = e }
            if isSecure { props[.secure] = "TRUE" }
            return HTTPCookie(properties: props)
        }
    }

    static func save(_ cookies: [HTTPCookie]) {
        let saved = cookies.map { SavedCookie(from: $0) }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [HTTPCookie] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([SavedCookie].self, from: data)
        else { return [] }

        return saved.compactMap { $0.toHTTPCookie() }
            .filter { cookie in
                if let exp = cookie.expiresDate, exp < Date() { return false }
                return true
            }
    }

    static var hasValidCookies: Bool {
        load().contains { $0.name == "NID_SES" || $0.name == "NID_AUT" }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static var lastSyncDate: Date? {
        UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }
}
