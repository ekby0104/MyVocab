import SwiftUI
import SwiftData

struct WordEditView: View {
    enum Mode {
        case add
        case edit(Word)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var english: String = ""
    @State private var pronunciation: String = ""
    @State private var partOfSpeech: String = ""
    @State private var meaning: String = ""
    @State private var example: String = ""
    @State private var exampleKo: String = ""
    @State private var memo: String = ""

    @State private var showDuplicateAlert = false

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("단어 *") {
                    TextField("영어 단어", text: $english)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        TextField("발음 [선택]", text: $pronunciation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !english.isEmpty {
                            Button {
                                SpeechService.shared.speak(english)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    TextField("품사 (예: n., v., adj.)", text: $partOfSpeech)
                        .textInputAutocapitalization(.never)
                }

                Section("뜻 *") {
                    TextField("한글 뜻", text: $meaning, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("예문 (선택)") {
                    TextField("영어 예문", text: $example, axis: .vertical)
                        .lineLimit(2...4)
                        .autocorrectionDisabled()
                    TextField("예문 한글 번역", text: $exampleKo, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("메모 (선택)") {
                    TextField("개인 메모", text: $memo, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(isEdit ? "단어 편집" : "단어 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") { save() }
                        .disabled(!canSave)
                }
            }
            .alert("중복 단어", isPresented: $showDuplicateAlert) {
                Button("확인") {}
            } message: {
                Text("이미 동일한 영어 단어가 단어장에 있습니다.")
            }
            .onAppear { loadIfEdit() }
        }
    }

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
            // 중복 체크
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
}
