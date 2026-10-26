import Core
import SwiftUI

// MARK: - 開始シート（#675）

/// ツールバーの「はじめから」から開く、モード（ステージ制／エンドレス）と始める面を選ぶシート。
///
/// 枠は共通の `GameSetupSheet`、モードの選び方は麻雀の東風戦／一局戦（`MahjongStartSheet`）と
/// 同じセグメントのピッカー + 1 行の説明。ステージ制のときだけ下にワールドマップ（#798）が
/// 付く。選んだモードと面は `RunnerModel.newGame(startingAtStage:)` / `newGame(mode:)` で
/// 走行に焼き込まれ、走行中に読み替えられることはない（1局=1RuleSet）。
///
/// 並べ方は共通枠の 1 種類（常に `.large`。スタートボタンだけスクロール領域の外。#1415 で全ゲームに揃えた）。
/// 6 世界 × 6 面の格子は 3 列 × 2 段を 6 つ積むので、モードの節と合わせると `.medium` には
/// 収まらない。エンドレスを選んで格子が消えても**シートの高さは変えない**——
/// `.medium` から開く形にして開始ボタンを下端へ離す案を一度試したが、モードを切り替えるたびに
/// シートそのものの高さが変わり、会長QA「モーダルの長さも変わってるしよ」で差し戻しになった
/// （2026-09-16）。スクロールしないとボタンへ届かない煩わしさ自体は残っていたため
/// （会長指摘・2026-09-22）、シートの高さ判定（`.large`固定）はそのままにボタンだけ
/// スクロール領域の外へ出す形（現在の共通枠）にした。
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
    /// 操作の説明を開いているか。モードを切り替えても開閉はそのまま。
    @State private var showsDetails = false

    var body: some View {
        GameSetupSheet(
            kind: .solo,
            onboarding: RunnerOnboarding.guide(mode: mode),
            onStart: onStart, onCancel: onCancel
        ) {
            GameSetupSection(tr("モード")) {
                // 他ゲームの開始シートと同じ大きめのタイルに揃える（会長指摘・2026-09-23。
                // `.pickerStyle(.segmented)` は他より一回り小さく見えた）。
                HStack(spacing: 12) {
                    ForEach(RunnerMode.allCases) { option in
                        GameSetupChooser(
                            title: option.title, subtitle: "",
                            selected: mode == option, accent: Theme.Fill.coral
                        ) { mode = option }
                    }
                }
                Text(mode.summary)
                    .scaledFont(12, weight: .medium, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 選んでいるモードの遊び方の要点を、図つきでそのまま並べる（#2044。荷物運びパズルの開始シート #2132 と
            // 同じ型・会長指示「遷移リンクを貼るだけでは駄目」）。カードは「？」の遊び方シートと同じ部品。
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
            if mode == .stages {
                GameSetupSection(tr("ステージを選ぶ")) {
                    RunnerWorldMap(selectedStage: $selectedStage, reachedStage: reachedStage)
                }
                GameSetupSection(tr("おはなし")) {
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

    /// 走り出し・ジャンプの説明を開閉する行。別画面へは移らず、この場で下に広げる（荷物運びパズルと同じ）。
    private var detailsToggle: some View {
        Button {
            withGameAnimation(.easeInOut(duration: 0.2)) { showsDetails.toggle() }
        } label: {
            HStack {
                Label(tr("操作のくわしい説明"), systemImage: "hand.tap.fill")
                    .themeBody(15)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .scaledFont(13, weight: .bold)
                    .foregroundStyle(Theme.inkSub)
                    .rotationEffect(.degrees(showsDetails ? 180 : 0))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .popCard(corner: Theme.cornerSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .accessibilityValue(showsDetails ? tr("開いている") : tr("閉じている"))
    }
}
