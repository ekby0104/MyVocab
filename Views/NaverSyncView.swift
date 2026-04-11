import SwiftUI
import SwiftData
import WebKit

struct NaverLoginWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct NaverSyncView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("selectedWordbookId") private var selectedWordbookId: String = ""

    @State private var wordbookList: [Wordbook] = WordbookStorage.load()

    private var selectedWordbook: Wordbook {
        wordbookList.first { $0.id == selectedWordbookId } ?? .all
    }

    private var wordbookBinding: Binding<Wordbook> {
        Binding(
            get: { selectedWordbook },
            set: { selectedWordbookId = $0.id }
        )
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    NaverLoginWebView(webView: webView)

                    if isLoading {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text(loadingMessage).font(.subheadline)
                        }
                        .padding(30)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }

                VStack(spacing: 10) {
                    HStack {
                        Text("단어장").font(.subheadline)
                        Spacer()
                        Picker("단어장", selection: wordbookBinding) {
                            ForEach(wordbookList) { wb in
                                Text(wb.name).tag(wb)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 4)

                    HStack(spacing: 8) {
                        Button {
                            Task { await refreshList() }
                        } label: {
                            Label("목록 새로고침", systemImage: "list.bullet.rectangle")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading)

                        Button {
                            Task { await fetchWordbook() }
                        } label: {
                            Label("가져오기", systemImage: "arrow.down.circle.fill")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading)
                    }

                    HStack(spacing: 16) {
                        Button { webView.goBack() } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .disabled(!webView.canGoBack)

                        Button { webView.load(URLRequest(url: Self.loginURL)) } label: {
                            Image(systemName: "house")
                        }

                        Spacer()

                        Button { webView.reload() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .font(.title3)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .navigationTitle("네이버 로그인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
            .alert("결과", isPresented: $showResult) {
                Button("확인") { if isSuccess { dismiss() } }
            } message: {
                Text(resultMessage ?? "")
            }
        }
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
            isSuccess = false   // 목록만 갱신, 시트는 닫지 않음
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
