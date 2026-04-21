import SwiftUI

/// 앱 전체에서 사용하는 디자인 토큰.
/// - 컨셉: 흰색 바탕 · 무채색 중심 · 최소한의 의미 컬러 · 시스템 폰트 기준
enum Theme {
    // MARK: - Colors

    /// 기본 잉크(강조 텍스트/버튼 배경). 다크모드에선 자동으로 밝은 톤.
    static let ink: Color = .primary

    /// 보조 텍스트
    static let muted: Color = .secondary

    /// 카드/행 배경
    static let surface: Color = Color(.systemBackground)

    /// 하위 영역/섹션 배경
    static let surfaceSecondary: Color = Color(.secondarySystemBackground)

    /// 구분선
    static let line: Color = Color(.opaqueSeparator)

    /// 옅은 그레이 (버튼, 칩 배경)
    static let chipBg: Color = Color(.systemGray6)

    // MARK: - Semantic (최소한만)

    static let favorite: Color = Color(red: 0.96, green: 0.70, blue: 0.16)  // #F5A524
    static let correct:  Color = Color(red: 0.09, green: 0.51, blue: 0.36)  // #17825D
    static let wrong:    Color = Color(red: 0.90, green: 0.28, blue: 0.30)  // #E5484D
    static let link:     Color = Color(red: 0.23, green: 0.51, blue: 0.96)  // #3B82F6

    // MARK: - Radius

    static let radiusCard: CGFloat = 12
    static let radiusButton: CGFloat = 10
    static let radiusChip: CGFloat = 6
}

// MARK: - Typography Helpers

extension Font {
    /// 리스트 행의 메인 단어 (13pt semibold) — mockup `.en`
    static let vocabTitle = Font.system(size: 13, weight: .semibold)
    /// 품사 표시 (10pt italic) — mockup `.pos`
    static let vocabPos = Font.system(size: 10, weight: .medium).italic()
    /// 한글 뜻 (12pt) — mockup `.ko`
    static let vocabBody = Font.system(size: 12, weight: .regular)
    /// 발음 (11pt) — mockup `.pron`
    static let vocabMuted = Font.system(size: 11, weight: .regular)
    /// 칩/태그 (9pt) — mockup `.chip`
    static let vocabChip = Font.system(size: 9, weight: .medium)
}

// MARK: - View Modifiers

extension View {
    /// 카드 스타일: 흰색 바탕 + 얇은 테두리 + 기본 radius
    func cardStyle(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard)
                    .stroke(Theme.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    /// 모노톤 주요 버튼 (검정 바탕 · 흰색 텍스트)
    func primaryButtonStyle() -> some View {
        self
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.ink)
            .foregroundStyle(Color(.systemBackground))
            .font(.system(size: 14, weight: .semibold))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusButton))
    }

    /// 아웃라인 보조 버튼
    func secondaryButtonStyle() -> some View {
        self
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .foregroundStyle(Theme.ink)
            .font(.system(size: 14, weight: .medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusButton)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

// MARK: - Small Chip Component

struct VocabChip: View {
    enum Kind {
        case neutral, wrong, favorite, correct

        var fg: Color {
            switch self {
            case .neutral:  return Theme.muted
            case .wrong:    return Theme.wrong
            case .favorite: return Color(red: 0.72, green: 0.53, blue: 0.10)
            case .correct:  return Theme.correct
            }
        }

        var bg: Color {
            switch self {
            case .neutral:  return Theme.chipBg
            case .wrong:    return Theme.wrong.opacity(0.10)
            case .favorite: return Color(red: 1.0, green: 0.97, blue: 0.90)
            case .correct:  return Theme.correct.opacity(0.10)
            }
        }
    }

    let text: String
    var kind: Kind = .neutral

    var body: some View {
        Text(text)
            .font(.vocabChip)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(kind.bg)
            .foregroundStyle(kind.fg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusChip))
    }
}
