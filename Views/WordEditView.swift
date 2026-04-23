import SwiftUI
import SwiftData

// MARK: - WordEditView (목업 구조 · custom topBar + field groups)

struct WordEditView: View {
    enum Mode {
        case add
        case edit(Word)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var english: String = ""
    @State private var pronunciation: String = ""
    @State private var partOfSpeech: String = ""
    @State private var meaning: String = ""
    @State private var example: String = ""
    @State private var exampleKo: String = ""
    @State private var memo: String = ""

    @State private var showDuplicateAlert = false
    @State private var showDeleteAlert = false

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editTarget: Word? {
        if case .edit(let w) = mode { return w }
        return nil
    }

    private var canSave: Bool {
        !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 0) {
                        wordGroup
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        meaningGroup
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        exampleGroup
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        memoGroup
                            .padding(.horizontal, 20)
                            .padding(.bottom, isEdit ? 16 : 24)

                        if isEdit {
                            deleteSection
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .background(Theme.surface)
            .navigationBarHidden(true)
            .alert("중복 단어", isPresented: $showDuplicateAlert) {
                Button("확인") {}
            } message: {
                Text("이미 동일한 영어 단어가 단어장에 있습니다.")
            }
            .alert("단어 삭제", isPresented: $showDeleteAlert) {
                Button("취소", role: .cancel) {}
                Button("삭제", role: .destructive) { deleteWord() }
            } message: {
                Text("'\(editTarget?.english ?? "")' 을(를) 삭제할까요?\n이 작업은 되돌릴 수 없어요.")
            }
            .onAppear { loadIfEdit() }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Text("취소")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.chipBg)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(isEdit ? "단어 편집" : "단어 추가")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Spacer()

            Button { save() } label: {
                Text("저장")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canSave ? Color(.systemBackground) : Theme.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(canSave ? Theme.ink : Theme.chipBg)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Delete section (edit only)

    private var deleteSection: some View {
        Button { showDeleteAlert = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                Text("이 단어 삭제")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Theme.wrong)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.wrong.opacity(0.35), lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Groups

    private var wordGroup: some View {
        editGroup(title: "단어", required: true) {
            field {
                TextField("영어 단어", text: $english)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14, weight: .semibold))
            }
            divider
            field {
                HStack {
                    TextField("발음 [선택]", text: $pronunciation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.muted)

                    if !english.isEmpty {
                        Button {
                            SpeechService.shared.speak(english)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 24, height: 24)
                                .background(Theme.chipBg)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            divider
            field {
                TextField("품사 (예: n., v., adj.)", text: $partOfSpeech)
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 12))
            }
        }
    }

    private var meaningGroup: some View {
        editGroup(title: "뜻", required: true) {
            field {
                TextField("한글 뜻", text: $meaning, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.system(size: 13))
            }
        }
    }

    private var exampleGroup: some View {
        editGroup(title: "예문", required: false) {
            field {
                TextField("영어 예문", text: $example, axis: .vertical)
                    .lineLimit(2...4)
                    .autocorrectionDisabled()
                    .font(.system(size: 12))
            }
            divider
            field {
                TextField("예문 한글 번역", text: $exampleKo, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var memoGroup: some View {
        editGroup(title: "메모", required: false) {
            field {
                TextField("개인 메모", text: $memo, axis: .vertical)
                    .lineLimit(15...30)
                    .font(.system(size: 12))
            }
        }
    }

    // MARK: - Building blocks

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
    }

    @ViewBuilder
    private func editGroup<Content: View>(
        title: String,
        required: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .tracking(0.5)
                if required {
                    Text("*")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.wrong)
                } else {
                    Text("(선택)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
            }
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

    @ViewBuilder
    private func field<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    // MARK: - Load / Save

    private func loadIfEdit() {
        if case .edit(let word) = mode {
            english = word.english
            pronunciation = word.pronunciation
            partOfSpeech = word.partOfSpeech
            meaning = word.meaning
            example = word.example
            exampleKo = word.exampleKo
            memo = word.memo
        }
    }

    private func save() {
        let trimmedEnglish = english.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .add:
            let descriptor = FetchDescriptor<Word>()
            let all = (try? context.fetch(descriptor)) ?? []
            if all.contains(where: { $0.english.lowercased() == trimmedEnglish.lowercased() }) {
                showDuplicateAlert = true
                return
            }

            let word = Word(
                english: trimmedEnglish,
                pronunciation: pronunciation.trimmingCharacters(in: .whitespacesAndNewlines),
                partOfSpeech: partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines),
                meaning: meaning.trimmingCharacters(in: .whitespacesAndNewlines),
                example: example.trimmingCharacters(in: .whitespacesAndNewlines),
                exampleKo: exampleKo.trimmingCharacters(in: .whitespacesAndNewlines),
                memo: memo.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            context.insert(word)

        case .edit(let word):
            word.english = trimmedEnglish
            word.pronunciation = pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
            word.partOfSpeech = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
            word.meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            word.example = example.trimmingCharacters(in: .whitespacesAndNewlines)
            word.exampleKo = exampleKo.trimmingCharacters(in: .whitespacesAndNewlines)
            word.memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        try? context.save()
        dismiss()
    }

    private func deleteWord() {
        guard let target = editTarget else { return }
        context.delete(target)
        try? context.save()
        dismiss()
    }
}
