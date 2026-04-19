import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var allWords: [Word]
    @AppStorage("selectedWordbookId") private var selectedWordbookId: String = ""

    @State private var wordbookList: [Wordbook] = WordbookStorage.load()

    @State private var showingImporter = false
    @State private var showingDeleteAlert = false
    @State private var showingNaverSync = false
    @State private var lastResult: NaverImporter.ImportResult? = nil
    @State private var errorMessage: String? = nil
    @State private var showLogSheet = false
    @State private var isQuickSyncing = false
    @State private var isRefreshingList = false
    @State private var quickSyncMessage: String? = nil
    @State private var showQuickSyncAlert = false
    @State private var hasValidCookies = CookieStorage.hasValidCookies
    @State private var lastSyncDate: Date? = CookieStorage.lastSyncDate

    // 백업/복원
    @State private var backupURL: URL? = nil
    @State private var showRestoreImporter = false
    @State private var backupAlertMessage: String? = nil
    @State private var showBackupAlert = false

    private var selectedWordbook: Wordbook {
        wordbookList.first { $0.id == selectedWordbookId } ?? .all
    }

    private var wordbookBinding: Binding<Wordbook> {
        Binding(
            get: { selectedWordbook },
            set: { selectedWordbookId = $0.id }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                naverSyncSection
                dataSection
                backupSection
                resultSection
                infoSection
            }
            .navigationTitle("⚙️ 설정")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .fileImporter(
                isPresented: $showRestoreImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleRestore(result)
            }
            .sheet(isPresented: $showingNaverSync, onDismiss: {
                hasValidCookies = CookieStorage.hasValidCookies
                lastSyncDate = CookieStorage.lastSyncDate
                wordbookList = WordbookStorage.load()
            }) {
                NaverSyncView()
            }
            .sheet(item: $backupURL) { url in
                ShareSheet(items: [url])
            }
            .sheet(isPresented: $showLogSheet) {
                if let result = lastResult {
                    SkippedLogView(result: result)
                }
            }
            .alert("전체 삭제", isPresented: $showingDeleteAlert) {
                Button("취소", role: .cancel) {}
                Button("삭제", role: .destructive) { deleteAll() }
            } message: {
                Text("모든 단어가 삭제됩니다. 되돌릴 수 없습니다.")
            }
            .alert("오류", isPresented: .constant(errorMessage != nil)) {
                Button("확인") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("동기화", isPresented: $showQuickSyncAlert) {
                Button("확인") {}
                if quickSyncMessage?.contains("세션") == true || quickSyncMessage?.contains("로그인") == true {
                    Button("다시 로그인") { showingNaverSync = true }
                }
            } message: {
                Text(quickSyncMessage ?? "")
            }
            .alert("백업/복원", isPresented: $showBackupAlert) {
                Button("확인") {}
            } message: {
                Text(backupAlertMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var naverSyncSection: some View {
        Section("네이버 동기화") {
            Picker(selection: wordbookBinding) {
                ForEach(wordbookList) { wb in
                    Text(wb.name).tag(wb)
                }
            } label: {
                Label("단어장", systemImage: "books.vertical")
            }

            Button {
                Task { await refreshWordbookList() }
            } label: {
                HStack {
                    if isRefreshingList {
                        ProgressView().controlSize(.small).padding(.trailing, 4)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("단어장 목록 새로고침")
                            .foregroundStyle(hasValidCookies ? Color.primary : Color.secondary)
                        Text(wordbookList.count > 1
                             ? "\(wordbookList.count - 1)개 단어장 불러옴"
                             : "아직 목록을 가져오지 않았어요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!hasValidCookies || isRefreshingList)

            Button {
                Task { await quickSync() }
            } label: {
                HStack {
                    if isQuickSyncing {
                        ProgressView().controlSize(.small).padding(.trailing, 4)
                    } else {
                        Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(selectedWordbook.name) 빠른 동기화")
                            .foregroundStyle(hasValidCookies ? Color.primary : Color.secondary)
                        if let date = lastSyncDate {
                            Text("마지막: \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !hasValidCookies {
                            Text("먼저 네이버 로그인이 필요합니다")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .disabled(!hasValidCookies || isQuickSyncing)

            Button {
                showingNaverSync = true
            } label: {
                Label(
                    hasValidCookies ? "네이버 재로그인" : "네이버 로그인",
                    systemImage: "globe"
                )
            }

            if hasValidCookies {
                Button(role: .destructive) {
                    CookieStorage.clear()
                    WordbookStorage.clear()
                    hasValidCookies = false
                    lastSyncDate = nil
                    wordbookList = WordbookStorage.load()
                } label: {
                    Label("저장된 로그인 삭제", systemImage: "key.slash")
                }
            }
        }
    }

    @ViewBuilder
    private var dataSection: some View {
        Section("데이터") {
            LabeledContent("저장된 단어", value: "\(allWords.count)개")

            Button {
                showingImporter = true
            } label: {
                Label("JSON 파일 불러오기", systemImage: "square.and.arrow.down")
            }

            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("전체 단어 삭제", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        Section("백업 / 복원") {
            Button {
                backupNow()
            } label: {
                Label("백업 파일 만들기", systemImage: "arrow.up.doc")
            }

            Button {
                showRestoreImporter = true
            } label: {
                Label("백업 파일에서 복원", systemImage: "arrow.down.doc")
            }

            Text("백업 파일은 단어 + 즐겨찾기 + 메모 + 통계까지 모두 저장합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let result = lastResult {
            Section("최근 불러오기 결과") {
                LabeledContent("추가됨", value: "\(result.inserted)개")
                LabeledContent("건너뜀", value: "\(result.skipped)개")

                ForEach(Array(result.skippedCounts.keys.sorted { $0.rawValue < $1.rawValue }), id: \.self) { reason in
                    LabeledContent("  └ \(reason.rawValue)", value: "\(result.skippedCounts[reason] ?? 0)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !result.skippedItems.isEmpty {
                    Button {
                        showLogSheet = true
                    } label: {
                        Label("건너뛴 단어 보기", systemImage: "list.bullet.rectangle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var infoSection: some View {
        Section("정보") {
            LabeledContent("버전", value: "1.0")
        }
    }

    // MARK: - Actions

    @MainActor
    private func refreshWordbookList() async {
        isRefreshingList = true
        defer { isRefreshingList = false }

        do {
            let list = try await NaverSync.refreshWordbookList()
            wordbookList = list
            quickSyncMessage = "단어장 \(list.count - 1)개를 불러왔어요"
            showQuickSyncAlert = true
        } catch NaverSync.SyncError.sessionExpired {
            hasValidCookies = false
            quickSyncMessage = "세션이 만료되었습니다. 다시 로그인해주세요."
            showQuickSyncAlert = true
        } catch NaverSync.SyncError.notLoggedIn {
            hasValidCookies = false
            quickSyncMessage = "로그인 정보가 없습니다. 네이버 로그인을 먼저 해주세요."
            showQuickSyncAlert = true
        } catch {
            quickSyncMessage = "실패: \(error.localizedDescription)"
            showQuickSyncAlert = true
        }
    }

    @MainActor
    private func quickSync() async {
        isQuickSyncing = true
        defer { isQuickSyncing = false }

        do {
            let data = try await NaverSync.quickSync(wordbook: selectedWordbook)
            let result = try NaverImporter.importJSON(data: data, context: context)
            lastResult = result
            lastSyncDate = CookieStorage.lastSyncDate
            quickSyncMessage = "[\(selectedWordbook.name)] 추가 \(result.inserted)개 · 건너뜀 \(result.skipped)개"
            showQuickSyncAlert = true
        } catch NaverSync.SyncError.sessionExpired {
            hasValidCookies = false
            quickSyncMessage = "세션이 만료되었습니다. 다시 로그인해주세요."
            showQuickSyncAlert = true
        } catch NaverSync.SyncError.notLoggedIn {
            hasValidCookies = false
            quickSyncMessage = "로그인 정보가 없습니다. 네이버 로그인을 먼저 해주세요."
            showQuickSyncAlert = true
        } catch {
            quickSyncMessage = "실패: \(error.localizedDescription)"
            showQuickSyncAlert = true
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let res = try NaverImporter.importJSON(data: data, context: context)
            lastResult = res
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func backupNow() {
        do {
            backupURL = try BackupService.exportToFile(context: context)
        } catch {
            backupAlertMessage = "백업 실패: \(error.localizedDescription)"
            showBackupAlert = true
        }
    }

    private func handleRestore(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let res = try BackupService.restore(data: data, context: context, replaceAll: false)
            backupAlertMessage = "복원 완료: \(res.restored)개 단어"
            showBackupAlert = true
        } catch {
            backupAlertMessage = "복원 실패: \(error.localizedDescription)"
            showBackupAlert = true
        }
    }

    private func deleteAll() {
        for w in allWords { context.delete(w) }
        try? context.save()
        lastResult = nil
    }
}

// MARK: - Skipped Log Sheet

struct SkippedLogView: View {
    let result: NaverImporter.ImportResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("전체", value: "\(result.skipped)개")
                    ForEach(Array(result.skippedCounts.keys.sorted { $0.rawValue < $1.rawValue }), id: \.self) { reason in
                        LabeledContent(reason.rawValue, value: "\(result.skippedCounts[reason] ?? 0)개")
                    }
                } header: {
                    Text("요약")
                }

                Section {
                    ForEach(result.skippedItems.indices, id: \.self) { i in
                        let item = result.skippedItems[i]
                        HStack {
                            Text(item.name)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(item.reason.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(color(for: item.reason).opacity(0.2))
                                .foregroundStyle(color(for: item.reason))
                                .clipShape(Capsule())
                        }
                    }
                } header: {
                    Text("건너뛴 단어 목록")
                }
            }
            .navigationTitle("건너뛴 단어")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func color(for reason: NaverImporter.SkipReason) -> Color {
        switch reason {
        case .duplicate:   return .blue
        case .emptyWord:   return .orange
        case .parseFailed: return .red
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
