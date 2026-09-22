import Core
import SwiftUI

// MARK: - 開始シート（#675）

/// 「はじめから」で開く、モード（ステージ制／エンドレス）と始める面を選ぶシート。
///
/// 枠は共通の `GameSetupSheet`、モードの選び方は麻雀の東風戦／一局戦（`MahjongStartSheet`）と
/// 同じセグメントのピッカー + 1 行の説明。ステージ制のときだけ下にワールドマップ（#798）が
/// 付く。選んだモードと面は `RunnerModel.newGame(startingAtStage:)` / `newGame(mode:)` で
/// 走行に焼き込まれ、走行中に読み替えられることはない（1局=1RuleSet）。
///
/// 並べ方は `.scrollingPinnedStart`（常に `.large`。スタートボタンだけスクロール領域の外）。
/// 5 世界 × 6 面の格子は 3 列 × 2 段を 5 つ積むので、モードの節と合わせると `.medium` には
/// 収まらない。エンドレスを選んで格子が消えても**シートの高さは変えない**——
/// 単純な `pinnedStart` にして開始ボタンを下端へ離す案を一度試したが、モードを切り替えるたびに
/// シートそのものの高さが変わり、会長QA「モーダルの長さも変わってるしよ」で差し戻しになった
/// （2026-09-16）。スクロールしないとボタンへ届かない煩わしさ自体は残っていたため
/// （会長指摘・2026-09-22）、シートの高さ判定（`.large`固定）はそのままにボタンだけ
/// スクロール領域の外へ出す `scrollingPinnedStart` を新設した。
struct RunnerStartSheet: View {
    @Binding var mode: RunnerMode
    /// ワールドマップで選んでいる面（1 始まり）。
    @Binding var selectedStage: Int
    /// 到達した最大の面。これより先は鍵付きで押せない（`RunnerModel.reachedStage`）。
    let reachedStage: Int
    /// 「おはなし」の見返しに並べる場面を決めるための記録（#1092）。
    let playLog: PlayLog?
    let onStart: () -> Void
    let onCancel: () -> Void

    /// 見返している場面（#1092）。シートの上に重ねるので、開始シート自身は閉じない。
    @State private var replayScene: RunnerStoryScene?

    var body: some View {
        GameSetupSheet(
            title: "はじめから", startTitle: "スタート", layout: .scrollingPinnedStart,
            onStart: onStart, onCancel: onCancel
        ) {
            GameSetupSection("モード") {
                Picker("モード", selection: $mode) {
                    ForEach(RunnerMode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text(mode.summary)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if mode == .stages {
                GameSetupSection("ステージを選ぶ") {
                    RunnerWorldMap(selectedStage: $selectedStage, reachedStage: reachedStage)
                }
                GameSetupSection("おはなし") {
                    RunnerStoryReplayList(playLog: playLog) { replayScene = $0 }
                }
            }
        }
        .overlay {
            if let scene = replayScene {
                RunnerStoryView(scene: scene) { replayScene = nil }
            }
        }
    }
}
