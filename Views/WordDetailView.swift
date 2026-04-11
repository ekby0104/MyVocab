import SwiftUI
import SwiftData

struct WordDetailView: View {
    @Bindable var word: Word
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 단어 + 품사
                HStack(alignment: .firstTextBaseline) {
                    Text(word.english).font(.largeTitle.bold())
                    if !word.partOfSpeech.isEmpty {
                        Text(word.partOfSpeech)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        word.isFavorite.toggle()
                        try? context.save()
                    } label: {
                        Image(systemName: word.isFavorite ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(.yellow)
                    }
                }

                // 발음
                if !word.pronunciation.isEmpty {
                    Text(word.pronunciation)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // 뜻
                if !word.meaning.isEmpty {
                    section(title: "뜻") {
                        Text(word.meaning).font(.body)
                    }
                }

                // 예문
                if !word.example.isEmpty {
                    section(title: "예문") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(word.example).font(.body)
                            if !word.exampleKo.isEmpty {
                                Text(word.exampleKo)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // 학습 통계
                section(title: "학습 통계") {
                    HStack(spacing: 24) {
                        stat(label: "정답", value: "\(word.correctCount)", color: .green)
                        stat(label: "오답", value: "\(word.wrongCount)", color: .red)
                        if let last = word.lastReviewedAt {
                            stat(
                                label: "최근",
                                value: last.formatted(date: .abbreviated, time: .omitted),
                                color: .blue
                            )
                        }
                    }
                }

                // 메모
                section(title: "메모") {
                    TextField("메모 입력", text: $word.memo, axis: .vertical)
                        .lineLimit(3...)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: word.memo) { _, _ in try? context.save() }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func stat(label: String, value: String, color: Color) -> some View {
        VStack {
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
