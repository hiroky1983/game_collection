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
    /// ゲーム行がタップされたとき（#1974）。シートを閉じてからハブがそのゲームを開く。
    var onOpenGame: (String) -> Void = { _ in }
    /// 「Game Center で見る」を押したとき。シートを閉じてからハブが開く
    /// （シートを出したまま Game Center のオーバーレイやサインイン画面を重ねない）。
    var onOpenGameCenter: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    Text(tr("節目"))
                }

                // MARK: あそびごと
                Section {
                    ForEach(Array(summary.rows.enumerated()), id: \.element.gameID) { index, row in
                        if let module = registry.module(id: row.gameID) {
                            gameRow(row, module: module, index: index)
                        }
                    }
                } header: {
                    Text(tr("あそびごと"))
                }

                // MARK: Game Center
                Section {
                    Button { onOpenGameCenter() } label: {
                        Label(tr("Game Center で実績・ランキングを見る"), systemImage: "trophy")
                    }
                    .foregroundStyle(Theme.ink)
                } footer: {
                    Text(tr("この画面の記録はこの端末にだけ保存しているもので、Game Center にサインインしなくても見られます。設定の「プレイ記録を消去」で消えます。"))
                }
            }
            .navigationTitle(tr("きろく"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("完了")) { dismiss() }
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
                    .tint(Theme.coral) // accent-text-ok: 進捗バーの塗り（面）
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary.progressText)

            // 6 枚を 3 枚ずつ 2 段に折る（タイルの数は固定。SE でも 1 枚あたり幅が足りる）。
            // 最大サイズでは見出しが切れるので 2 枚ずつ 3 段にする（#2935）。
            let tiles = statTiles(summary)
            let columns = dynamicTypeSize.isAccessibilitySize ? 2 : 3
            VStack(spacing: 8) {
                ForEach(0..<(tiles.count / columns), id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<columns, id: \.self) { column in
                            let tile = tiles[row * columns + column]
                            statTile(title: tile.title, value: tile.value, note: tile.note)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statTiles(_ summary: RecordsSummary) -> [(title: String, value: String, note: String?)] {
        let streak = playLog?.playStreak() ?? 0
        let longest = playLog?.longestPlayStreak() ?? 0
        return [
            (tr("遊んだ種類"), "\(summary.playedCount)/\(summary.gameCount)", nil),
            (tr("通算勝利"), RecordFormat.number(summary.totalWins), nil),
            (tr("最高連勝"), RecordFormat.number(summary.bestStreak), nil),
            (tr("総プレイ回数"), tr("%@回", RecordFormat.number(playLog?.totalFinishes ?? 0)), nil),
            // `playDays` は直近 366 日ぶんだけ保存している（上限を超えた古い日は数えない）。
            (tr("遊んだ日数"), tr("%@日", RecordFormat.number(playLog?.playDays.count ?? 0)), nil),
            // 日をまたぐ連続（#1625）。勝敗の連勝とは別物。0 日のときも 0 で出す（タイルの数は固定）。
            // 途切れても最長が残るよう「最長 N 日」を添える（#2886）。
            (tr("連続日数"), tr("%@日", RecordFormat.number(streak)),
             PlayDayStreak.showsLongest(current: streak, longest: longest)
                ? tr("最長 %@ 日", RecordFormat.number(longest)) : nil),
        ]
    }

    private func statTile(title: String, value: String, note: String?) -> some View {
        VStack(spacing: 2) {
            // 数値は整形済みの文字列で渡す（`Text` の補間に Int を渡すと桁区切りが勝手に入る）。
            Text(verbatim: value)
                .themeTitle(22)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .themeCaption(11)
                .foregroundStyle(Theme.inkSubText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.7)
            if let note {
                Text(verbatim: note)
                    .themeCaption(11)
                    .foregroundStyle(Theme.inkSubText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .fill(Theme.coral.opacity(0.1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.map { tr("%1$@、%2$@、%3$@", title, value, $0) } ?? tr("%1$@、%2$@", title, value))
    }

    private func milestoneRow(_ milestone: RecordsSummary.Milestone) -> some View {
        HStack(spacing: 12) {
            Image(systemName: milestone.isAchieved ? "checkmark.seal.fill" : "seal")
                .scaledFont(20, weight: .semibold)
                .foregroundStyle(milestone.isAchieved ? Theme.coralText : Theme.inkSubText)
            Text(milestone.title)
                .themeBody(16)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Text(verbatim: milestone.isAchieved ? tr("達成") : milestone.progressText)
                .themeCaption(13)
                .foregroundStyle(milestone.isAchieved ? Theme.coralText : Theme.inkSubText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(milestone.accessibilityLabel)
    }

    private func gameRow(_ row: RecordsSummary.Row, module: GameModule, index: Int) -> some View {
        Button { onOpenGame(row.gameID) } label: {
            gameRowContent(row, module: module, index: index)
        }
        .buttonStyle(.pop)
        .accessibilityHint(tr("タップでこのゲームを開きます"))
    }

    private func gameRowContent(_ row: RecordsSummary.Row, module: GameModule, index: Int) -> some View {
        // 最後に遊んだ日（#2871）。開くたびに今の日付で数え直す（保存しない）。
        let lastPlayedText = row.lastPlayedText(now: Date())
        return HStack(spacing: 12) {
            // 差し色は設定シートと同じく並びの位置で引く。
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.Fill.palette[index % Theme.Fill.palette.count].gradient)
                .frame(width: 32, height: 32)
                .overlay {
                    module.icon
                        .scaledFont(16, weight: .bold)
                        .foregroundStyle(Theme.onAccent)
                }
                .opacity(row.isPlayed ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .themeBody(16)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: row.detailText)
                    .themeCaption(12)
                    .foregroundStyle(Theme.inkSubText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.7)
                if let lastPlayedText {
                    Text(verbatim: lastPlayedText)
                        .themeCaption(12)
                        .foregroundStyle(Theme.inkSubText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if !row.milestones.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(row.milestones, id: \.self) { milestone in
                            Text(row.milestoneTitle(milestone))
                                .themeCaption(10)
                                .foregroundStyle(Theme.coralText)
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
                    .foregroundStyle(Theme.inkSubText)
            } else {
                // まだ遊んでいない行は「あそぶ」を出して、押せると分かるようにする（#1974）。
                Text(tr("あそぶ"))
                    .themeCaption(13)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.coralText)
            }
            Image(systemName: "chevron.right")
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(Theme.inkSubText.opacity(0.6))
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        // 行をばらばらに読ませず、ゲーム名から 1 行ずつ読ませる（受け入れ条件）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel(lastPlayedText: lastPlayedText))
    }
}
