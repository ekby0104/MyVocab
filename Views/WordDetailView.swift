import SwiftUI
import SwiftData

// MARK: - WordDetailView (목업 구조 · detail-hero + detail-section)

struct WordDetailView: View {
    @Bindable var word: Word
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var showEdit = false
    @State private var showResetAlert = false
    @FocusState private var memoFocused: Bool

    private var accuracyPercent: Int {
        let total = word.correctCount + word.wrongCount
        guard total > 0 else { return 0 }
        return Int(Double(word.correctCount) / Double(total) * 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: 0) {
                    hero

                    if !word.meaning.isEmpty {
                        section(title: "뜻") {
                            Text(word.meaning)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .lineSpacing(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !word.example.isEmpty || !word.exampleKo.isEmpty {
                        section(title: "예문") {
                            VStack(alignment: .leading, spacing: 6) {
                                if !word.example.isEmpty {
                                    HStack(alignment: .top, spacing: 8) {
                                        highlightedExample(word.example, highlight: word.english)
                                        Spacer(minLength: 0)
                                        Button { SpeechService.shared.speak(word.example) } label: {
                                            Image(systemName: "speaker.wave.2")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Theme.ink)
                                                .frame(width: 24, height: 24)
                                                .background(Theme.chipBg)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                if !word.exampleKo.isEmpty {
                                    Text(word.exampleKo)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.muted)
                                        .lineSpacing(2)
                                }
                            }
                        }
                    }

                    section(title: "SRS · 레벨 \(word.srsLevel) / \(SRSService.maxLevel)\(srsSubtitle)") {
                        srsBadges
                    }

                    section(title: "학습 기록") {
                        statInline
                        if word.correctCount > 0 || word.wrongCount > 0 || word.isWrong {
                            resetControls
                                .padding(.top, 10)
                        }
                    }

                    section(title: "메모", isLast: true) {
                        TextField("메모 입력", text: $word.memo, axis: .vertical)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2...)
                            .focused($memoFocused)
                            .onChange(of: memoFocused) { _, focused in
                                if !focused { try? context.save() }
                            }
                            .padding(10)
                            .background(Theme.chipBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.surface)
        .navigationBarHidden(true)
        .sheet(isPresented: $showEdit) {
            WordEditView(mode: .edit(word))
        }
        .alert("학습 기록 초기화", isPresented: $showResetAlert) {
            Button("취소", role: .cancel) {}
            Button("초기화", role: .destructive) {
                word.wrongCount = 0
                word.correctCount = 0
                word.isWrong = false
                word.srsLevel = 0
                word.nextReviewDate = nil
                word.lastReviewedAt = nil
                try? context.save()
            }
        } message: {
            Text("정답/오답 카운트, SRS 레벨, 복습 기록이 모두 초기화됩니다.")
        }
    }

    // MARK: - Top bar (mockup: ← · center meta · ✎)

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Theme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Spacer()

            if let last = word.lastReviewedAt {
                Text("최근 복습 · \(last.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            } else {
                Text("미학습")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            Button {
                showEdit = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Theme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !word.partOfSpeech.isEmpty {
                Text(word.partOfSpeech)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .italic()
                    .padding(.bottom, 2)
            }

            HStack(alignment: .center, spacing: 12) {
                Text(word.english)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .tracking(-0.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Button {
                        word.isFavorite.toggle()
                        try? context.save()
                    } label: {
                        Image(systemName: word.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundStyle(word.isFavorite ? Theme.favorite : Theme.ink)
                            .frame(width: 34, height: 34)
                            .background(Theme.chipBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button {
                        word.isHard.toggle()
                        try? context.save()
                    } label: {
                        Image(systemName: word.isHard ? "flame.fill" : "flame")
                            .font(.system(size: 14))
                            .foregroundStyle(word.isHard ? Theme.hard : Theme.ink)
                            .frame(width: 34, height: 34)
                            .background(Theme.chipBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button {
                        SpeechService.shared.speak(word.english)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 34, height: 34)
                            .background(Theme.chipBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)

            if !word.pronunciation.isEmpty {
                Text(word.pronunciation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 6)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Section helper

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        isLast: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .tracking(0.5)
            content()
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - SRS badges (mockup .srs-dot)

    private var srsBadges: some View {
        HStack(spacing: 4) {
            ForEach(0...SRSService.maxLevel, id: \.self) { lv in
                let on = lv <= word.srsLevel
                let cur = lv == word.srsLevel
                Text("\(lv)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(on ? Color.white : Theme.muted)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(on ? Theme.ink : Theme.chipBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.ink, lineWidth: cur ? 1.5 : 0)
                            .padding(-2)
                    )
            }
        }
    }

    private var srsSubtitle: String {
        if let next = word.nextReviewDate {
            let days = Calendar.current.dateComponents([.day], from: .now, to: next).day ?? 0
            if days <= 0 { return " · 오늘 복습 가능" }
            return " · \(days)일 후 복습"
        }
        return " · 미학습"
    }

    // MARK: - Stat inline (mockup .stat-inline)

    private var statInline: some View {
        HStack(spacing: 16) {
            statItem(n: "\(word.correctCount)", label: "정답")
            statItem(n: "\(word.wrongCount)", label: "오답")
            statItem(n: "\(accuracyPercent)%", label: "정답률")
            Spacer()
        }
    }

    private func statItem(n: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(n)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
                .tracking(-0.2)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Reset controls

    private var resetControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if word.correctCount > 0 {
                    smallButton(icon: "minus.circle", label: "정답 카운트 초기화") {
                        word.correctCount = 0
                        try? context.save()
                    }
                }
                if word.wrongCount > 0 {
                    smallButton(icon: "minus.circle", label: "오답 카운트 초기화") {
                        word.wrongCount = 0
                        try? context.save()
                    }
                }
                if word.isWrong {
                    smallButton(icon: "checkmark.circle", label: "틀린 단어 해제") {
                        word.isWrong = false
                        try? context.save()
                    }
                }
                smallButton(icon: "arrow.counterclockwise", label: "전체 초기화") {
                    showResetAlert = true
                }
            }
        }
    }

    private func smallButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Highlighted example

    @ViewBuilder
    private func highlightedExample(_ full: String, highlight: String) -> some View {
        let parts = full.splittingAround(highlight, caseInsensitive: true)
        HStack(spacing: 0) {
            Text(makeAttributed(parts: parts))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func makeAttributed(parts: [(String, Bool)]) -> AttributedString {
        var out = AttributedString("")
        for (p, isMatch) in parts {
            var s = AttributedString(p)
            if isMatch {
                s.inlinePresentationIntent = .stronglyEmphasized
                s.underlineStyle = .single
            }
            out.append(s)
        }
        return out
    }
}

// MARK: - String splitting helper

private extension String {
    func splittingAround(_ target: String, caseInsensitive: Bool) -> [(String, Bool)] {
        guard !target.isEmpty else { return [(self, false)] }
        var result: [(String, Bool)] = []
        var remaining = self[...]
        let opts: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []
        while !remaining.isEmpty {
            if let range = remaining.range(of: target, options: opts) {
                if range.lowerBound > remaining.startIndex {
                    result.append((String(remaining[remaining.startIndex..<range.lowerBound]), false))
                }
                result.append((String(remaining[range]), true))
                remaining = remaining[range.upperBound...]
            } else {
                result.append((String(remaining), false))
                break
            }
        }
        return result
    }
}
