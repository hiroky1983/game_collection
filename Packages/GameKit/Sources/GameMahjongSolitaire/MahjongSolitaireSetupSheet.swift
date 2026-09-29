import SwiftUI
import Core

/// 盤面のかたちを選ぶ開始シート（#239 の選択を「＋」メニューから移した・会長 QA 2026-09-28）。
///
/// ほかのゲームの難易度選びと同じく、**中断データが無い初回はこのシートから始め**、ナビバーの
/// 「新規ゲーム」でも開く。中断データがあるときは出さずに続きから。枠は共通の `GameSetupSheet`。
///
/// **ここで選んだかたちは配牌と同時に焼き込まれ、その局の途中では変えられない**（1局=1RuleSet）。
/// 途中の盤面があるときは同じ警告をここに出し、確定のボタンを「終了してスタート」にする
/// （旧・確認ダイアログ「終了して新規ゲーム」の役目をこのシートが兼ねる。ソリティア #498 と同じ）。
struct MahjongSolitaireSetupSheet: View {
    @Binding var draft: MahjongSolitaireLayout
    /// 途中の盤面を捨てて配り直すことになるか。文言だけを切り替える。
    let discardsProgress: Bool
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        GameSetupSheet(
            kind: .solo, discardsProgress: discardsProgress,
            onStart: onStart, onCancel: onCancel
        ) {
            sections
        }
    }

    /// シートの中身（節と警告）。枠の外でも描いて確かめられるよう分けてある。
    @ViewBuilder var sections: some View {
        GameSetupSection("盤面のかたち") {
            HStack(spacing: 6) {
                // 並び順は `MahjongSolitaireLayout.all`（亀甲・ピラミッド・十字）。
                ForEach(MahjongSolitaireLayout.all) { layout in
                    GameSetupChooser(title: layout.displayName, subtitle: "",
                                     selected: draft == layout, accent: Theme.Fill.teal,
                                     metrics: DifficultyTile.metrics) {
                        draft = layout
                    }
                }
            }
            Text("どのかたちも144枚で、必ず取り切れるように配ります。最短タイムはかたちごとに別々に記録されます。")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
        }
        if discardsProgress {
            Label("途中で終了すると今の盤面が失われます。",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.coral)
        }
    }
}
