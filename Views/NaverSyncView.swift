import SwiftUI
import SwiftData
import WebKit

// MARK: - NaverSyncView (목업 구조 · custom topBar + webview + bottom control card)

struct NaverLoginWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct NaverSyncView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.displayScale) private var displayScale
    @AppStorage("selectedWordbookId") private var selectedWordbookId: String = ""

    @State private var wordbookList: [Wordbook] = WordbookStorage.load()
    @State private var showWordbookPicker = false

    private var selectedWordbook: Wordbook {
        wordbookList.first { $0.id == selectedWordbookId } ?? .all
    }

    private static let loginURL = URL(string: "https://nid.naver.com/nidlogin.login")!

    @State private var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.load(URLRequest(url: NaverSyncView.loginURL))
        return wv
    }()

    @State private var isLoading = false
    @State private var loadingMessage = ""
    @State private var resultMessage: String? = nil
    @State private var showResult = false
    @State private var isSuccess = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ZStack {
                NaverLoginWebView(webView: webView)

                if isLoading {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text(loadingMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(22)
                    .background(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.line, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            controlBar
        }
        .background(Theme.surface)
        .alert("결과", isPresented: $showResult) {
            Button("확인") { if isSuccess { dismiss() } }
        } message: {
            Text(resultMessage ?? "")
        }
        .sheet(isPresented: $showWordbookPicker) {
            wordbookPickerSheet
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Theme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("네이버 로그인")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Spacer()

            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Control bar

    private var controlBar: some View {
        VStack(spacing: 10) {
            // WebView navigation
            HStack(spacing: 8) {
                iconButton(systemName: "chevron.backward", disabled: !webView.canGoBack) {
                    webView.goBack()
                }
                iconButton(systemName: "house") {
                    webView.load(URLRequest(url: Self.loginURL))
                }
                iconButton(systemName: "arrow.clockwise") {
                    webView.reload()
                }

                Spacer()

                Button { showWordbookPicker = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 11))
                        Text(selectedWordbook.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    Task { await refreshList() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 11))
                        Text("목록 새로고침")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.line, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)

                Button {
                    Task { await fetchWordbook() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11))
                        Text("가져오기")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            Rectangle()
                .fill(Theme.surface)
                .overlay(
                    Rectangle()
                        .fill(Theme.line)
                        .frame(height: 1 / displayScale),
                    alignment: .top
                )
                .ignoresSafeArea(.container, edges: .bottom)
        )
    }

    private func iconButton(systemName: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(Theme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Wordbook picker

    private var wordbookPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("닫기") { showWordbookPicker = false }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("단어장 선택")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("닫기").font(.system(size: 13)).opacity(0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(wordbookList.enumerated()), id: \.element.id) { idx, wb in
                        Button {
                            selectedWordbookId = wb.id
                            showWordbookPicker = false
                        } label: {
                            HStack {
                                Text(wb.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                if wb.id == selectedWordbookId {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if idx < wordbookList.count - 1 {
                            Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
                        }
                    }
                }
                .background(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.line, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.surface)
    }

    // MARK: - Actions

    @MainActor
    private func refreshList() async {
        isLoading = true
        loadingMessage = "단어장 목록 불러오는 중..."
        defer { isLoading = false }

        do {
            let list = try await NaverSync.fetchWordbookListWithWebView(webView: webView)
            wordbookList = list
            resultMessage = "단어장 \(list.count - 1)개를 찾았습니다\n(전체 포함 \(list.count)개)"
            isSuccess = false
            showResult = true
        } catch {
            resultMessage = "목록 불러오기 실패: \(error.localizedDescription)"
            isSuccess = false
            showResult = true
        }
    }

    @MainActor
    private func fetchWordbook() async {
        isLoading = true
        loadingMessage = "단어장 가져오는 중..."
        defer { isLoading = false }

        do {
            let data = try await NaverSync.fetchWithWebViewCookies(
                webView: webView,
                wordbook: selectedWordbook
            )
            let result = try NaverImporter.importJSON(data: data, context: context)

            var msg = "[\(selectedWordbook.name)] 추가 \(result.inserted)개 · 건너뜀 \(result.skipped)개"
            if !result.skippedItems.isEmpty {
                let counts = result.skippedCounts
                    .map { "\($0.key.rawValue) \($0.value)개" }
                    .joined(separator: ", ")
                msg += "\n\(counts)"
            }
            resultMessage = msg
            isSuccess = result.inserted > 0
            showResult = true
        } catch {
            resultMessage = "실패: \(error.localizedDescription)"
            isSuccess = false
            showResult = true
        }
    }
}
