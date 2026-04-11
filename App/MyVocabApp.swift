import SwiftUI
import SwiftData
import UIKit

@main
struct MyVocabApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Word.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // 개발 중 스키마 변경 시 DB 초기화
            print("ModelContainer 생성 실패, DB 삭제 후 재시도: \(error)")
            if let url = config.url as URL? {
                try? FileManager.default.removeItem(at: url)
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("재생성도 실패: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onOpenURL { url in
                    if url.scheme == "myvocab" {
                        handleCustomScheme(url)
                    } else {
                        handleIncomingFile(url)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - 파일 공유로 들어온 경우

    private func handleIncomingFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let context = sharedModelContainer.mainContext
            let result = try NaverImporter.importJSON(data: data, context: context)
            let msg = "추가 \(result.inserted)개 · 건너뜀 \(result.skipped)개"
            NotificationCenter.default.post(name: .vocabImported, object: msg)
        } catch {
            NotificationCenter.default.post(
                name: .vocabImported,
                object: "불러오기 실패: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - myvocab:// 스킴 (단축어에서 호출)

    /// myvocab://import 호출 시 클립보드에서 JSON 읽어 import
    private func handleCustomScheme(_ url: URL) {
        guard url.host == "import" else {
            NotificationCenter.default.post(
                name: .vocabImported,
                object: "알 수 없는 명령: \(url.absoluteString)"
            )
            return
        }

        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NotificationCenter.default.post(
                name: .vocabImported,
                object: "클립보드가 비어있습니다.\n단축어가 JSON을 복사했는지 확인하세요."
            )
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") {
            NotificationCenter.default.post(
                name: .vocabImported,
                object: "클립보드에 HTML이 있습니다.\n네이버 로그인 상태를 확인하세요."
            )
            return
        }

        guard let data = trimmed.data(using: .utf8) else {
            NotificationCenter.default.post(
                name: .vocabImported,
                object: "클립보드 내용을 변환할 수 없습니다."
            )
            return
        }

        do {
            let context = sharedModelContainer.mainContext
            let result = try NaverImporter.importJSON(data: data, context: context)
            var msg = "단축어로 가져오기 완료\n추가 \(result.inserted)개 · 건너뜀 \(result.skipped)개"
            if !result.skippedItems.isEmpty {
                let counts = result.skippedCounts
                    .map { "\($0.key.rawValue) \($0.value)개" }
                    .joined(separator: ", ")
                msg += "\n(\(counts))"
            }
            NotificationCenter.default.post(name: .vocabImported, object: msg)
        } catch {
            NotificationCenter.default.post(
                name: .vocabImported,
                object: "파싱 실패: \(error.localizedDescription)"
            )
        }
    }
}
