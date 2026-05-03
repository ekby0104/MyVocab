import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - SettingsView (목업 구조 · profile-card + settings-group/srow)

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.displayScale) private var displayScale
    @Query private var allWords: [Word]
    @AppStorage("selectedWordbookId") private var selectedWordbookId: String = ""
    @AppStorage("learningMode") private var learningModeRaw: String = LearningMode.intensive.rawValue

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

    @State private var backupURL: URL? = nil
    @State private var showRestoreImporter = false
    @State private var backupAlertMessage: String? = nil
    @State private var showBackupAlert = false

    @State private var showWordbookPicker = false

    private var selectedWordbook: Wordbook {
        wordbookList.first { $0.id == selectedWordbookId } ?? .all
    }

    private var favoriteCount: Int { allWords.filter(\.isFavorite).count }
    private var masteredCount: Int { allWords.filter { $0.srsLevel >= 5 }.count }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 0) {
                        profileCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)

                        naverGroup
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        learningModeGroup
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        dataGroup
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        backupGroup
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        if lastResult != nil {
                            resultGroup
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                        }

                        infoGroup
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .background(Theme.surface)
            .navigationBarHidden(true)
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { handleImport($0) }
            .fileImporter(
                isPresented: $showRestoreImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { handleRestore($0) }
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
            .sheet(isPresented: $showWordbookPicker) {
                wordbookPickerSheet
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

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Text("설정")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .tracking(-0.5)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Profile card

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Theme.chipBg)
                    Image(systemName: "person.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.muted)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text("나의 단어장")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .tracking(-0.2)
                    Text(selectedWordbook.name)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }

                Spacer()
            }
            .padding(.bottom, 12)

            // Ribbon (metrics)
            HStack(spacing: 0) {
                ribbonItem(value: "\(allWords.count)", label: "단어")
                Rectangle().fill(Theme.line).frame(width: 0.5, height: 28)
                ribbonItem(value: "\(favoriteCount)", label: "즐겨찾기")
                Rectangle().fill(Theme.line).frame(width: 0.5, height: 28)
                ribbonItem(value: "\(masteredCount)", label: "마스터")
            }
            .padding(.vertical, 10)
            .background(Theme.chipBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func ribbonItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Settings groups

    private var naverGroup: some View {
        settingsGroup(title: "네이버 동기화") {
            srow(
                icon: "books.vertical",
                title: "단어장",
                sub: selectedWordbook.name,
                trailing: .chevron,
                action: { showWordbookPicker = true }
            )
            srow(
                icon: "arrow.triangle.2.circlepath",
                title: "단어장 목록 새로고침",
                sub: wordbookList.count > 1
                    ? "\(wordbookList.count - 1)개 단어장 불러옴"
                    : "아직 목록을 가져오지 않았어요",
                trailing: isRefreshingList ? .progress : .chevron,
                disabled: !hasValidCookies || isRefreshingList,
                action: { Task { await refreshWordbookList() } }
            )
            srow(
                icon: "bolt",
                title: "\(selectedWordbook.name) 빠른 동기화",
                sub: quickSyncSubtitle,
                trailing: isQuickSyncing ? .progress : .chevron,
                disabled: !hasValidCookies || isQuickSyncing,
                action: { Task { await quickSync() } }
            )
            srow(
                icon: "globe",
                title: hasValidCookies ? "네이버 재로그인" : "네이버 로그인",
                sub: hasValidCookies ? "현재 로그인됨" : "웹뷰로 로그인",
                trailing: .chevron,
                isLast: !hasValidCookies,
                action: { showingNaverSync = true }
            )
            if hasValidCookies {
                srow(
                    icon: "key.slash",
                    title: "저장된 로그인 삭제",
                    sub: "쿠키 · 단어장 목록 제거",
                    trailing: .chevron,
                    destructive: true,
                    isLast: true,
                    action: {
                        CookieStorage.clear()
                        WordbookStorage.clear()
                        hasValidCookies = false
                        lastSyncDate = nil
                        wordbookList = WordbookStorage.load()
                    }
                )
            }
        }
    }

    private var quickSyncSubtitle: String {
        if !hasValidCookies { return "먼저 네이버 로그인이 필요합니다" }
        if let date = lastSyncDate {
            return "마지막: \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "동기화 기록 없음"
    }

    private var currentLearningMode: LearningMode {
        LearningMode(rawValue: learningModeRaw) ?? .intensive
    }

    private var learningModeGroup: some View {
        settingsGroup(
            title: "학습 모드",
            subtitle: "복습 간격을 학습 목적에 맞게 선택하세요"
        ) {
            ForEach(Array(LearningMode.allCases.enumerated()), id: \.element.id) { idx, mode in
                let isLast = idx == LearningMode.allCases.count - 1
                Button {
                    learningModeRaw = mode.rawValue
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 24, height: 24)
                            .background(Theme.chipBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Text(mode.description)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                            Text(intervalSummary(for: mode))
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.muted)
                                .padding(.top, 2)
                        }

                        Spacer()

                        Image(systemName: currentLearningMode == mode ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(currentLearningMode == mode ? Theme.ink : Theme.line)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !isLast {
                    Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
                }
            }
        }
    }

    /// 모드별 간격 요약 텍스트
    private func intervalSummary(for mode: LearningMode) -> String {
        let days = mode.intervalsInDays.dropFirst()  // Lv.0 (즉시) 제외
        return "Lv.1~7: " + days.map { "\($0)일" }.joined(separator: " · ")
    }

    private var dataGroup: some View {
        settingsGroup(title: "데이터") {
            srow(
                icon: "number",
                title: "저장된 단어",
                sub: "\(allWords.count)개",
                trailing: .none
            )
            srow(
                icon: "square.and.arrow.down",
                title: "JSON 파일 불러오기",
                sub: "파일에서 가져오기",
                trailing: .chevron,
                action: { showingImporter = true }
            )
            srow(
                icon: "trash",
                title: "전체 단어 삭제",
                sub: "되돌릴 수 없음",
                trailing: .chevron,
                destructive: true,
                isLast: true,
                action: { showingDeleteAlert = true }
            )
        }
    }

    private var backupGroup: some View {
        settingsGroup(
            title: "백업 / 복원",
            subtitle: "단어 + 즐겨찾기 + 메모 + 통계까지 전부 저장됩니다."
        ) {
            srow(
                icon: "arrow.up.doc",
                title: "백업 파일 만들기",
                sub: "공유 시트로 내보내기",
                trailing: .chevron,
                action: { backupNow() }
            )
            srow(
                icon: "arrow.down.doc",
                title: "백업 파일에서 복원",
                sub: "병합 방식으로 가져오기",
                trailing: .chevron,
                isLast: true,
                action: { showRestoreImporter = true }
            )
        }
    }

    @ViewBuilder
    private var resultGroup: some View {
        if let result = lastResult {
            settingsGroup(title: "최근 불러오기 결과") {
                resultRow(label: "추가됨", value: "\(result.inserted)개")
                resultRow(label: "건너뜀", value: "\(result.skipped)개")

                let sortedReasons = Array(result.skippedCounts.keys.sorted { $0.rawValue < $1.rawValue })
                let hasSkippedItems = !result.skippedItems.isEmpty

                ForEach(Array(sortedReasons.enumerated()), id: \.offset) { idx, reason in
                    resultRow(
                        label: "  └ \(reason.rawValue)",
                        value: "\(result.skippedCounts[reason] ?? 0)개",
                        muted: true,
                        isLast: !hasSkippedItems && idx == sortedReasons.count - 1
                    )
                }

                if hasSkippedItems {
                    srow(
                        icon: "list.bullet.rectangle",
                        title: "건너뛴 단어 보기",
                        sub: "\(result.skippedItems.count)개",
                        trailing: .chevron,
                        isLast: true,
                        action: { showLogSheet = true }
                    )
                }
            }
        }
    }

    private var infoGroup: some View {
        settingsGroup(title: "정보") {
            srow(
                icon: "info.circle",
                title: "버전",
                sub: "1.0",
                trailing: .none,
                isLast: true
            )
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func settingsGroup<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .tracking(0.5)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            content()
        }
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    enum SRowTrailing {
        case chevron, progress, none
    }

    @ViewBuilder
    private func srow(
        icon: String,
        title: String,
        sub: String,
        trailing: SRowTrailing = .chevron,
        disabled: Bool = false,
        destructive: Bool = false,
        isLast: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(destructive ? Theme.wrong : Theme.ink)
                    .frame(width: 24, height: 24)
                    .background(destructive ? Theme.wrong.opacity(0.10) : Theme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(destructive ? Theme.wrong : Theme.ink)
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }

                Spacer()

                switch trailing {
                case .chevron:
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.line)
                case .progress:
                    ProgressView().controlSize(.small)
                case .none:
                    EmptyView()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .opacity(disabled ? 0.4 : 1)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled || action == nil)
    }

    private func resultRow(label: String, value: String, muted: Bool = false, isLast: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: muted ? 11 : 13, weight: muted ? .regular : .medium))
                .foregroundStyle(muted ? Theme.muted : Theme.ink)
            Spacer()
            Text(value)
                .font(.system(size: muted ? 11 : 13, weight: muted ? .regular : .semibold))
                .foregroundStyle(muted ? Theme.muted : Theme.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
            }
        }
    }

    // MARK: - Wordbook picker sheet

    private var wordbookPickerSheet: some View {
        NavigationStack {
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
                                .overlay(alignment: .bottom) {
                                    if idx < wordbookList.count - 1 {
                                        Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
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
            .navigationBarHidden(true)
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
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button("닫기") { dismiss() }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("건너뛴 단어")
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
                        // 요약
                        VStack(spacing: 0) {
                            Text("요약")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .tracking(0.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                .padding(.bottom, 6)

                            let sortedReasons = Array(result.skippedCounts.keys.sorted { $0.rawValue < $1.rawValue })

                            summaryRow(
                                label: "전체",
                                value: "\(result.skipped)개",
                                bold: true,
                                isLast: sortedReasons.isEmpty
                            )

                            ForEach(Array(sortedReasons.enumerated()), id: \.offset) { idx, reason in
                                summaryRow(
                                    label: reason.rawValue,
                                    value: "\(result.skippedCounts[reason] ?? 0)개",
                                    isLast: idx == sortedReasons.count - 1
                                )
                            }
                        }
                        .background(Theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.line, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)

                        // 목록
                        VStack(spacing: 0) {
                            Text("건너뛴 단어 목록")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .tracking(0.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                .padding(.bottom, 6)

                            ForEach(result.skippedItems.indices, id: \.self) { i in
                                let item = result.skippedItems[i]
                                HStack {
                                    Text(item.name)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text(item.reason.rawValue)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(color(for: item.reason))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(color(for: item.reason).opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .overlay(alignment: .bottom) {
                                    if i < result.skippedItems.count - 1 {
                                        Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
                                    }
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
                        .padding(.bottom, 24)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .background(Theme.surface)
            .navigationBarHidden(true)
        }
    }

    private func summaryRow(label: String, value: String, bold: Bool = false, isLast: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: bold ? .semibold : .regular))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: bold ? .semibold : .regular))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
            }
        }
    }

    private func color(for reason: NaverImporter.SkipReason) -> Color {
        switch reason {
        case .duplicate:   return Theme.muted
        case .emptyWord:   return Theme.favorite
        case .parseFailed: return Theme.wrong
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
