import SwiftUI
import SwiftData

struct StatsView: View {
    @Query private var allWords: [Word]
    @State private var selectedLevel: Int? = nil

    private var totalWords: Int { allWords.count }
    private var favoriteCount: Int { allWords.filter(\.isFavorite).count }
    private var wrongCount: Int { allWords.filter(\.isWrong).count }

    private var totalCorrect: Int { allWords.reduce(0) { $0 + $1.correctCount } }
    private var totalWrong: Int { allWords.reduce(0) { $0 + $1.wrongCount } }
    private var totalAttempts: Int { totalCorrect + totalWrong }

    private var accuracyPercent: Int {
        guard totalAttempts > 0 else { return 0 }
        return Int(Double(totalCorrect) / Double(totalAttempts) * 100)
    }

    private var studiedCount: Int {
        allWords.filter { $0.lastReviewedAt != nil }.count
    }

    private var masteredCount: Int {
        allWords.filter { $0.srsLevel >= 5 }.count
    }

    /// 가장 자주 틀리는 단어 TOP 10 (오답 1회 이상만)
    private var topWrongWords: [Word] {
        allWords
            .filter { $0.wrongCount > 0 }
            .sorted { $0.wrongCount > $1.wrongCount }
            .prefix(10)
            .map { $0 }
    }

    /// SRS 레벨 분포
    private var levelDistribution: [(level: Int, count: Int)] {
        let dist = SRSService.levelDistribution(from: allWords)
        return (0...SRSService.maxLevel).map { level in
            (level: level, count: dist[level] ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 요약 카드들
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        statCard(title: "전체 단어", value: "\(totalWords)", icon: "books.vertical.fill", color: .blue)
                        statCard(title: "학습 완료", value: "\(studiedCount)", icon: "graduationcap.fill", color: .green)
                        statCard(title: "마스터", value: "\(masteredCount)", icon: "crown.fill", color: .purple)
                        statCard(title: "정답률", value: "\(accuracyPercent)%", icon: "target", color: .orange)
                        statCard(title: "즐겨찾기", value: "\(favoriteCount)", icon: "star.fill", color: .yellow)
                        statCard(title: "틀린 단어", value: "\(wrongCount)", icon: "xmark.circle.fill", color: .red)
                    }
                    .padding(.horizontal)

                    // 정답/오답 누적
                    if totalAttempts > 0 {
                        attemptCard
                            .padding(.horizontal)
                    }

                    // SRS 레벨 분포
                    levelCard
                        .padding(.horizontal)

                    // 자주 틀리는 단어 TOP 10
                    if !topWrongWords.isEmpty {
                        topWrongCard
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top)
            }
            .navigationTitle("통계")
            .background(Color(.systemGroupedBackground))
            .sheet(item: $selectedLevel) { level in
                LevelWordsView(level: level, allWords: allWords)
            }
        }
    }

    // MARK: - Components

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var attemptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("학습 누적")
                .font(.headline)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.green)
                    .frame(width: barWidth(for: totalCorrect))
                Rectangle()
                    .fill(Color.red)
                    .frame(width: barWidth(for: totalWrong))
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Label("정답 \(totalCorrect)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Label("오답 \(totalWrong)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func barWidth(for count: Int) -> CGFloat {
        guard totalAttempts > 0 else { return 0 }
        let ratio = CGFloat(count) / CGFloat(totalAttempts)
        // UIScreen 대신 GeometryReader가 정확하지만 단순화
        return UIScreen.main.bounds.width * 0.85 * ratio
    }

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SRS 레벨 분포")
                .font(.headline)
            Text("높은 레벨일수록 잘 외운 단어")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(levelDistribution, id: \.level) { item in
                Button {
                    if item.count > 0 {
                        selectedLevel = item.level
                    }
                } label: {
                    HStack {
                        Text("Lv.\(item.level)")
                            .font(.caption.monospaced())
                            .frame(width: 36, alignment: .leading)
                        GeometryReader { geo in
                            let maxCount = max(levelDistribution.map(\.count).max() ?? 1, 1)
                            let width = CGFloat(item.count) / CGFloat(maxCount) * geo.size.width
                            Rectangle()
                                .fill(levelColor(item.level))
                                .frame(width: width, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .frame(height: 16)
                        Text("\(item.count)")
                            .font(.caption.monospaced())
                            .frame(width: 40, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        if item.count > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(item.count == 0)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func levelColor(_ level: Int) -> Color {
        switch level {
        case 0: return .red
        case 1, 2: return .orange
        case 3, 4: return .yellow
        case 5, 6: return .green
        default: return .purple
        }
    }

    private var topWrongCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("자주 틀리는 단어 TOP 10")
                .font(.headline)

            ForEach(Array(topWrongWords.enumerated()), id: \.element.id) { index, word in
                NavigationLink {
                    WordDetailView(word: word)
                } label: {
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(rankColor(index)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(word.english)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            if !word.meaning.isEmpty {
                                Text(word.meaning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("✗ \(word.wrongCount)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                    }
                }
                if index < topWrongWords.count - 1 {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return .red
        case 1: return .orange
        case 2: return .yellow
        default: return .gray
        }
    }
    
}
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Level Words View

struct LevelWordsView: View {
    let level: Int
    let allWords: [Word]
    @Environment(\.dismiss) private var dismiss

    private var words: [Word] {
        allWords.filter { $0.srsLevel == level }
            .sorted { $0.english.lowercased() < $1.english.lowercased() }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(words) { word in
                    NavigationLink {
                        WordDetailView(word: word)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(word.english)
                                    .font(.headline)
                                Spacer()
                                if word.isWrong {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                                if word.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            if !word.meaning.isEmpty {
                                Text(word.meaning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            HStack {
                                Text("✓\(word.correctCount)")
                                    .foregroundStyle(.green)
                                Text("✗\(word.wrongCount)")
                                    .foregroundStyle(.red)
                                if let date = word.lastReviewedAt {
                                    Text("최근: \(date.formatted(date: .abbreviated, time: .omitted))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption2)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Lv.\(level) 단어 (\(words.count)개)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
