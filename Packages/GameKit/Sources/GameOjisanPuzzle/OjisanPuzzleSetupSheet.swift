import SwiftUI
import Core

/// 始める前に遊び方（荷運びモード / パズルモード・#1920）を選ぶシート。共通の `GameSetupSheet` に節を足すだけ。
///
/// モードの違いが選ぶ場所で分かるよう、選択肢の下に**いま選んでいるモードの遊び方の要点を図つきでそのまま並べる**
/// （会長指示 2026-10-12「遊び方の概要を難易度（モード選択）のところで見せろ。遷移リンクを貼るだけでは駄目」）。
/// 中身は「？」と同じ `howToPlayGuide` の項目で、カードも遊び方シートと同じ部品（`HowToPlayItemCard`）。
/// モードの違いが出る項目（目的・腰痛ゲージ・おわり）は常に見せ、どちらも同じ操作・れんさの説明は折りたたむ。
struct OjisanPuzzleSetupSheet: View {
    /// 選んだ遊び方。`onStart` で局に焼き込まれる。
    @Binding var mode: OjisanPuzzleMode
    let onStart: () -> Void
    let onCancel: () -> Void
    /// 操作・れんさの説明を開いているか。モードを切り替えても開閉はそのまま。
    @State private var showsDetails = false

    var body: some View {
        GameSetupSheet(kind: .solo, onboarding: OjisanPuzzleOnboarding.guide(mode: mode), onStart: onStart, onCancel: onCancel) {
            GameSetupSection(tr("遊び方")) {
                HStack(spacing: 12) {
                    ForEach(OjisanPuzzleMode.allCases) { option in
                        GameSetupChooser(
                            title: option.title, subtitle: "",
                            selected: mode == option, accent: Theme.Fill.coral,
                            icon: option.setupIcon,
                            metrics: .init(title: .title(18), titleMinimumScale: 0.7)
                        ) { mode = option }
                    }
                }
            }
            GameSetupSection(tr("%@のルール", mode.title)) {
                VStack(spacing: 10) {
                    ForEach(Array(mode.setupKeyItems.enumerated()), id: \.offset) { _, item in
                        HowToPlayItemCard(item)
                    }
                    detailsToggle
                    if showsDetails {
                        ForEach(Array(mode.setupDetailItems.enumerated()), id: \.offset) { _, item in
                            HowToPlayItemCard(item)
                        }
                        let notes = mode.howToPlayGuide.notes
                        if !notes.isEmpty { HowToPlayNotesCard(notes) }
                    }
                }
                // モードを切り替えたら、前のモードの図を引きずらずに丸ごと描き直す。
                .id(mode)
            }
        }
    }

    /// 操作・れんさの説明を開閉する行。別画面へは移らず、この場で下に広げる。
    private var detailsToggle: some View {
        Button {
            withGameAnimation(.easeInOut(duration: 0.2)) { showsDetails.toggle() }
        } label: {
            HStack {
                Label(tr("操作・れんさのくわしい説明"), systemImage: "hand.draw.fill")
                    .themeBody(15)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .scaledFont(13, weight: .bold)
                    .foregroundStyle(Theme.inkSubText)
                    .rotationEffect(.degrees(showsDetails ? 180 : 0))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .popCard(corner: Theme.cornerSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pop)
        .foregroundStyle(Theme.ink)
        .accessibilityValue(showsDetails ? tr("開いている") : tr("閉じている"))
    }
}

extension OjisanPuzzleMode {
    /// このモードの図入りの遊び方。ゲーム画面ヘッダーの「？」と、開始シートに並べる要点で同じものを使う。
    @MainActor
    var howToPlayGuide: HowToPlayGuide {
        switch self {
        case .backpain: .ojisanPuzzleBackpain.illustrated(OjisanPuzzleHowToFigures.backpain)
        case .puzzle: .ojisanPuzzlePuzzle.illustrated(OjisanPuzzleHowToFigures.puzzle)
        }
    }

    /// 開始シートで常に見せる項目の位置（`howToPlayGuide.items` の添字）。モードの違いが分かるもの:
    /// 目的・腰痛ゲージ（荷運びモードだけ）・おわり方。
    var setupKeyItemIndices: [Int] {
        switch self {
        case .backpain: [0, 4, 5]
        case .puzzle: [0, 4]
        }
    }

    /// 開始シートで常に見せる項目（目的・腰痛ゲージ・おわり）。
    @MainActor
    var setupKeyItems: [HowToPlayItem] {
        let items = howToPlayGuide.items
        return setupKeyItemIndices.map { items[$0] }
    }

    /// 開始シートで折りたたむ項目（操作・れんさ・荷物の種類。両モード共通の説明）。
    @MainActor
    var setupDetailItems: [HowToPlayItem] {
        let keys = Set(setupKeyItemIndices)
        return howToPlayGuide.items.enumerated().filter { !keys.contains($0.offset) }.map(\.element)
    }
}
