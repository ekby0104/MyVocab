import SwiftUI
import SafariServices

// MARK: - 단어 상세에 들어가는 영영 사전 섹션 (v2)
// Free Dictionary API (https://dictionaryapi.dev)
// 추가 기능: UK/US 발음 구분, 오디오 재생, 어원, Wiktionary 링크

struct DictionarySection: View {
    let word: String
    @Environment(\.displayScale) private var displayScale
    @State private var service = DictionaryService()
    @StateObject private var audioPlayer = AudioPlayerService.shared

    @State private var state: LoadState = .idle
    @State private var info: DictionaryWordInfo?
    @State private var errorMessage: String?
    @State private var currentLoadedWord: String = ""
    @State private var showSafari = false
    @State private var safariURL: URL?

    enum LoadState {
        case idle, loading, success, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 헤더
            HStack(spacing: 6) {
                Text("영영 사전")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .tracking(0.5)

                Spacer()

                Button { Task { await load(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 22, height: 22)
                        .background(Theme.chipBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(state == .loading)
                .opacity(state == .loading ? 0.4 : 1)
            }

            // 내용
            content
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
        }
        .padding(.horizontal, 20)
        .onAppear {
            if currentLoadedWord != word {
                Task { await load(force: false) }
            }
        }
        .onChange(of: word) { _, newWord in
            if currentLoadedWord != newWord {
                Task { await load(force: false) }
            }
        }
        .onDisappear {
            audioPlayer.stop()
        }
        .sheet(isPresented: $showSafari) {
            if let url = safariURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("조회 중...")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 4)

        case .failed:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                Text(errorMessage ?? "조회 실패")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }

        case .success:
            if let info {
                successBody(info: info)
            }
        }
    }

    // MARK: - Success body

    private func successBody(info: DictionaryWordInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 발음 (UK/US 한 줄 컴팩트)
            if !info.pronunciations.isEmpty {
                pronunciationRow(info.pronunciations)
            }

            // 품사별 그룹
            ForEach(info.lexicalGroups) { group in
                lexicalGroupView(group: group)
            }

            // 어원
            if let origin = info.origin {
                originView(origin: origin)
            }

            // Wiktionary 링크
            if let url = info.wiktionaryURL {
                wiktionaryLink(url: url)
            }
        }
    }

    // MARK: - 발음 행

    private func pronunciationRow(_ items: [PronunciationItem]) -> some View {
        // FlowLayout으로 자동 줄바꿈
        FlowLayout(spacing: 10) {
            ForEach(items) { item in
                pronunciationChip(item: item)
            }
        }
    }

    private func pronunciationChip(item: PronunciationItem) -> some View {
        HStack(spacing: 6) {
            // 국기 (방언 미상이면 IPA 라벨)
            if item.dialect == .unknown {
                Text("IPA")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .tracking(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text(item.dialect.flag)
                    .font(.system(size: 14))
            }

            // IPA
            if let ipa = item.ipa, !ipa.isEmpty {
                Text(formatIPA(ipa))
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.ink)
            }

            // 오디오 버튼
            if let audioURL = item.audioURL {
                Button {
                    audioPlayer.play(audioURL)
                } label: {
                    Image(systemName: audioPlayer.isPlaying(audioURL) ? "speaker.wave.2.fill" : "speaker.wave.2")
                        .font(.system(size: 11))
                        .foregroundStyle(audioPlayer.isPlaying(audioURL) ? .blue : Theme.ink)
                        .frame(width: 22, height: 22)
                        .background(Theme.chipBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// IPA를 슬래시로 감싸서 표시 (이미 감싸져 있으면 그대로)
    private func formatIPA(_ ipa: String) -> String {
        let trimmed = ipa.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/") && trimmed.hasSuffix("/") {
            return trimmed
        }
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            return trimmed
        }
        return "/\(trimmed)/"
    }

    // MARK: - 어원

    private func originView(origin: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("어원")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .tracking(0.4)

            Text(origin)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink.opacity(0.8))
                .lineSpacing(2)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Wiktionary 링크

    private func wiktionaryLink(url: URL) -> some View {
        Button {
            safariURL = url
            showSafari = true
        } label: {
            HStack(spacing: 4) {
                Text("Wiktionary에서 자세히 보기")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Theme.muted)
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 품사별 그룹

    private func lexicalGroupView(group: LexicalGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.category.lowercased())
                .font(.system(size: 11, weight: .semibold))
                .italic()
                .foregroundStyle(Theme.muted)

            ForEach(Array(group.senses.enumerated()), id: \.element.id) { idx, sense in
                senseView(index: idx + 1, sense: sense)
            }
        }
    }

    private func senseView(index: Int, sense: DisplaySense) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text("\(index).")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 18, alignment: .leading)

                Text(sense.definition)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !sense.examples.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(sense.examples.prefix(2), id: \.self) { ex in
                        Text("\u{201C}\(ex)\u{201D}")
                            .font(.system(size: 12, design: .serif))
                            .italic()
                            .foregroundStyle(Theme.muted)
                            .lineSpacing(1)
                    }
                }
                .padding(.leading, 24)
                .padding(.top, 2)
            }

            if !sense.synonyms.isEmpty {
                wordChipsRow(label: "유의어", words: sense.synonyms, color: .green)
                    .padding(.leading, 24)
                    .padding(.top, 4)
            }

            if !sense.antonyms.isEmpty {
                wordChipsRow(label: "반의어", words: sense.antonyms, color: .red)
                    .padding(.leading, 24)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private func wordChipsRow(label: String, words: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color.opacity(0.8))
                .tracking(0.4)

            FlowLayout(spacing: 4) {
                ForEach(words.prefix(6), id: \.self) { w in
                    Text(w)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }

    // MARK: - Load

    private func load(force: Bool) async {
        let targetWord = word
        print("[DictionarySection] load 시작: '\(targetWord)', force=\(force), state=\(state), currentLoadedWord='\(currentLoadedWord)'")

        if state == .loading {
            print("[DictionarySection] 이미 로딩 중, 스킵")
            return
        }

        if !force, currentLoadedWord == targetWord, state != .idle {
            print("[DictionarySection] 같은 단어 이미 처리됨(\(state)), 스킵")
            return
        }

        if force {
            service.invalidateCache(for: targetWord)
        }

        info = nil
        errorMessage = nil
        state = .loading

        do {
            let result = try await service.lookup(targetWord)
            guard targetWord == word else {
                print("[DictionarySection] word 변경됨('\(targetWord)' → '\(word)'), 결과 무시")
                return
            }
            info = result
            currentLoadedWord = targetWord
            state = .success
            print("[DictionarySection] 성공: '\(targetWord)'")
        } catch let e as DictionaryService.DictError {
            guard targetWord == word else { return }
            errorMessage = e.errorDescription
            currentLoadedWord = targetWord
            state = .failed
            print("[DictionarySection] 실패: '\(targetWord)' - \(e.errorDescription ?? "?")")
        } catch {
            guard targetWord == word else { return }
            errorMessage = error.localizedDescription
            currentLoadedWord = targetWord
            state = .failed
            print("[DictionarySection] 실패: '\(targetWord)' - \(error.localizedDescription)")
        }
    }
}

// MARK: - SafariView (in-app 웹뷰)

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
