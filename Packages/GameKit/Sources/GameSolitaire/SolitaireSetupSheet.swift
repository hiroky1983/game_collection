import SwiftUI
import Core

/// 配り直すときにルールを選ぶ開始シート（#498）。
///
/// **ここで選んだ値は配札と同時に焼き込まれ、その局の途中では変えられない**
/// （`docs/ai-devops.md`「1局=1RuleSet」原則）。ソリティアは起動したらすぐ遊べるのが
/// 身上なので、**初回の配札ではこのシートを出さない**（既定の1枚めくりで即座に配る）。
/// 出るのはツールバーの「新規ゲーム」を押したときだけ。枠は共通の `GameSetupSheet`（#1416）。
///
/// #498 以前にそこで出していた確認ダイアログ（「新しい配札にしますか？」）は、
/// **このシートが兼ねる**。途中の盤面があるときは同じ警告をここに出し、
/// 確定のボタンを破棄扱いにする。ダイアログを残したままシートを重ねると、
/// キャンセルできる確認が 2 枚続くことになる。
public struct SolitaireSetupSheet: View {
    @Binding var draft: SolitaireRuleSet
    /// 途中の盤面を捨てて配り直すことになるか。文言だけを切り替える。
    let discardsProgress: Bool
    let onStart: () -> Void
    let onCancel: () -> Void

    public init(
        draft: Binding<SolitaireRuleSet>,
        discardsProgress: Bool,
        onStart: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._draft = draft
        self.discardsProgress = discardsProgress
        self.onStart = onStart
        self.onCancel = onCancel
    }

    public var body: some View {
        // 途中の盤面を捨てることになる場合だけ、開始ボタンが「終了してスタート」の確認文言になる
        // （旧・確認ダイアログの「終了して新規ゲーム」と同じ重み）。
        GameSetupSheet(
            kind: .solo, discardsProgress: discardsProgress,
            onStart: onStart, onCancel: onCancel
        ) {
            GameSetupSection("山札のめくり方") {
                HStack(spacing: 12) {
                    ForEach(SolitaireDrawMode.allCases, id: \.self) { mode in
                        GameSetupChooser(
                            title: mode.label, subtitle: "",
                            selected: draft.drawMode == mode, accent: Theme.Fill.teal
                        ) { draft.drawMode = mode }
                    }
                }
                Text(Self.footer(for: draft.drawMode))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
            }
            if discardsProgress {
                Label("途中で終了すると今の盤面が失われ、この配札は「クリアできなかった」として記録されます。",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.coral)
            }
        }
    }

    /// めくり方の説明。**記録の扱いまで書く**（自己ベストが別枠になり、順位表には
    /// 標準の1枚めくりしか載らないことを、選ぶ前に知らせる）。
    static func footer(for mode: SolitaireDrawMode) -> String {
        switch mode {
        case .one:
            return "山札を1枚ずつめくります。いちばん標準的なクロンダイクで、"
                + "Game Center の「ソリティア 最短タイム」に載るのはこちらだけです。"
        case .three:
            return "山札を3枚ずつめくり、使えるのはいちばん上の1枚だけです。"
                + "同じ配札でも使える札が減るぶん歯ごたえがあります。"
                + "自己ベストは1枚めくりとは別に記録され、Game Center の順位表には送りません。"
        }
    }
}
