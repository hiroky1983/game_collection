import SwiftUI
import Core

/// アプリ内「きろく」画面（#669）。全ゲームの自己ベスト・勝敗・連勝を 1 画面で見せる。
///
/// ハブのトロフィーから開くシート。Game Center 未サインインでも見られる（以前のトロフィーは
/// 未サインインだと案内のアラートで終わり、手元の記録を見る場所がハブカードの 1 行しか無かった）。
/// 数字と文言はすべて `RecordsSummary`（Core の純粋関数）が決め、この型は描くだけ。
/// **保存項目は増やさない**。開くたびに `PlayLog` から組み立て直す。
struct RecordsView: View {
    let registry: GameRegistry
    let settings: GameSettings
    /// プレイ記録。注入されないとき（プレビュー等）は全部「まだ遊んでいない」で出す。
    var playLog: PlayLog?
    /// 「Game Center で見る」を押したとき。シートを閉じてからハブが開く
    /// （シートを出したまま Game Center のオーバーレイやサインイン画面を重ねない）。
    var onOpenGameCenter: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// 並びは設定シートと同じ（非表示のゲームも記録は残っているので載せる）。
    private var summary: RecordsSummary {
        let games = settings.orderedIDs
            .compactMap { registry.module(id: $0) }
            .map { RecordsSummary.Game(id: $0.id, title: $0.title) }
        return playLog?.recordsSummary(games: games)
            ?? RecordsSummary.make(games: games, playedGameIDs: [], records: [:], totalWins: 0)
    }

    var body: some View {
        let summary = summary
        NavigationStack {
            List {
                // MARK: まとめ
                Section {
                    overview(summary)
                }

                // MARK: 節目
                Section {
                    ForEach(summary.milestones, id: \.achievementID) { milestone in
                        milestoneRow(milestone)
                    }
                } header: {
                    Text("節目")
                }

                // MARK: あそびごと
                Section {
                    ForEach(Array(summary.rows.enumerated()), id: \.element.gameID) { index, row in
                        if let module = registry.module(id: row.gameID) {
                            gameRow(row, module: module, index: index)
                        }
                    }
                } header: {
                    Text("あそびごと")
                }

                // MARK: Game Center
                Section {
                    Button { onOpenGameCenter() } label: {
                        Label("Game Center で実績・ランキングを見る", systemImage: "trophy")
                    }
                    .foregroundStyle(Theme.ink)
                } footer: {
                    Text("この画面の記録はこの端末にだけ保存しているもので、Game Center にサインインしなくても見られます。設定の「プレイ記録を消去」で消えます。")
                }
            }
            .navigationTitle("きろく")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func overview(_ summary: RecordsSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.progressText)
                    .themeBody(15)
                    .foregroundStyle(Theme.ink)
                ProgressView(value: Double(summary.playedCount), total: Double(max(summary.gameCount, 1)))
                    .tint(Theme.coral)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary.progressText)

            HStack(spacing: 8) {
                statTile(title: "遊んだ種類", value: "\(summary.playedCount)/\(summary.gameCount)")
                statTile(title: "通算勝利", value: RecordFormat.number(summary.totalWins))
                statTile(title: "最高連勝", value: RecordFormat.number(summary.bestStreak))
            }
        }
        .padding(.vertical, 4)
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            // 数値は整形済みの文字列で渡す（`Text` の補間に Int を渡すと桁区切りが勝手に入る）。
            Text(verbatim: value)
                .themeTitle(22)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .themeCaption(11)
                .foregroundStyle(Theme.inkSub)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .fill(Theme.coral.opacity(0.1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)、\(value)")
    }

    private func milestoneRow(_ milestone: RecordsSummary.Milestone) -> some View {
        HStack(spacing: 12) {
            Image(systemName: milestone.isAchieved ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(milestone.isAchieved ? Theme.coral : Theme.inkSub)
            Text(milestone.title)
                .themeBody(16)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Text(verbatim: milestone.isAchieved ? "達成" : milestone.progressText)
                .themeCaption(13)
                .foregroundStyle(milestone.isAchieved ? Theme.coral : Theme.inkSub)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(milestone.accessibilityLabel)
    }

    private func gameRow(_ row: RecordsSummary.Row, module: GameModule, index: Int) -> some View {
        HStack(spacing: 12) {
            // 差し色は設定シートと同じく並びの位置で引く。
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.Fill.palette[index % Theme.Fill.palette.count].gradient)
                .frame(width: 32, height: 32)
                .overlay {
                    module.icon
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                }
                .opacity(row.isPlayed ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .themeBody(16)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: row.detailText)
                    .themeCaption(12)
                    .foregroundStyle(Theme.inkSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !row.milestones.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(row.milestones, id: \.self) { milestone in
                            Text(row.milestoneTitle(milestone))
                                .themeCaption(10)
                                .foregroundStyle(Theme.coral)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.coral.opacity(0.12)))
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            if let plays = row.playsText {
                Text(verbatim: plays)
                    .themeCaption(13)
                    .foregroundStyle(Theme.inkSub)
            }
        }
        // 行をばらばらに読ませず、ゲーム名から 1 行ずつ読ませる（受け入れ条件）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
