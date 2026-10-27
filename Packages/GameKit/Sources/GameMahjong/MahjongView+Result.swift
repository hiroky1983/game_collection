import SwiftUI
import Core
import MahjongTiles

extension MahjongView {
    // MARK: - リザルト

    var handResultCard: some View {
        VStack(spacing: 8) {
            Text(handResultTitle)
                .scaledFont(20, weight: .black, design: .rounded)
                .foregroundStyle(Theme.coralText)
            if let result = model.handResult, result.kind != .exhaustiveDraw {
                Text(Self.hanFuLine(result))
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.ink)
                VStack(spacing: 3) {
                    ForEach(Array(result.yaku.enumerated()), id: \.offset) { _, line in
                        // 保存値（日本語）を表示言語にする（#2166）。
                        Text(MahjongHandResult.displayYakuLine(line))
                            .scaledFont(12, weight: .semibold, design: .rounded)
                            .foregroundStyle(Theme.inkSubText)
                    }
                }
                Text(Self.pointsText(result.gainedPoints))
                    .scaledFont(18, weight: .black, design: .rounded)
                    .foregroundStyle(Theme.tealText)
                // 和了者の手を開く（#351）。何に振り込んだか・どんな手だったかを学べるようにする。
                if let tiles = result.winningHand, let winTile = result.winningTile {
                    winningHandRow(
                        tiles: tiles, melds: result.winningMelds ?? [], winningTile: winTile
                    )
                }
                if let ura = result.uraDoraIndicators, !ura.isEmpty {
                    uraDoraRow(ura)
                }
            } else if let result = model.handResult {
                // 手牌は卓の上で開けてある（#2872）。ここは罰符の内訳を 1 行で。
                Text(Self.drawPenaltyLine(result))
                    .scaledFont(13, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            scoreTable
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 和了者の手（門前 + 副露 + 和了牌）。「なぜ負けたか」を学べるようにリザルトで開く（#351）。
    /// 和了牌は `isHinted` のハイライトで半歩離して並べ、どれで和了ったかをひと目で分かるようにする。
    private func winningHandRow(
        tiles: [MahjongTile], melds: [MahjongCall], winningTile: MahjongTile
    ) -> some View {
        let sorted = tiles.sorted { MahjongTileOrder.index(of: $0) < MahjongTileOrder.index(of: $1) }
        // 門前13枚 + 和了牌でもカード幅（約300pt）に収まる小ささ。副露があるぶん門前は減るので
        // これより横に伸びることはない。
        let tileWidth: CGFloat = 17
        let tileHeight: CGFloat = 23
        return HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, tile in
                    MahjongTileView(tile: tile, width: tileWidth, height: tileHeight)
                }
            }
            if !melds.isEmpty {
                MahjongMeldRow(melds: melds, tileWidth: tileWidth, showsBadge: false)
            }
            MahjongTileView(tile: winningTile, width: tileWidth, height: tileHeight, isHinted: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            tr("和了した手: %1$@、和了牌は %2$@",
               sorted.map(\.displayName).joined(separator: MahjongAccessibility.listSeparator),
               winningTile.displayName)
        )
    }

    /// 立直で和了ったときだけ開示する裏ドラ表示牌（#351）。卓中央のドラ表示と同じ牌サイズ。
    private func uraDoraRow(_ tiles: [MahjongTile]) -> some View {
        HStack(spacing: 4) {
            Text(tr("裏ドラ"))
                .scaledFont(11, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                MahjongTileView(tile: tile, width: 14, height: 19)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("裏ドラ表示牌: %@", tiles.map(\.displayName).joined(separator: MahjongAccessibility.listSeparator)))
    }

    /// 会長指摘「誰が誰に点を振り込んだかわかるようにしてほしい」への対応。ロンは放銃した人が
    /// 一意に決まるので、タイトルに「{放銃した人} → {和了した人}」を添える。ツモは複数人が
    /// 別々の額を払うため、単一の矢印では表せない。下の `scoreTable` 側で全員の点数の動きを
    /// 一覧できるようにして補う。
    private var handResultTitle: String {
        guard let result = model.handResult else { return "" }
        let winnerName = model.playerName(result.winner ?? 0)
        switch result.kind {
        case .exhaustiveDraw: return tr("流局")
        case .tsumo:  return tr("%@のツモ", winnerName)
        case .ron:
            guard let loser = result.loser else { return tr("%@のロン", winnerName) }
            return tr("%1$@ → %2$@のロン", model.playerName(loser), winnerName)
        }
    }

    /// 終わり方は3種類あり、東2局で突然終わっても理由が読めるよう見出しを分ける（#352）。
    /// 打ち切りの見出しは対局の長さで変える（#639。一局戦で「東風戦終了」と出ると嘘になる）。
    private var gameResultTitle: String {
        switch model.gameEndReason {
        case .busted:    return tr("トビで終了")
        case .agariYame: return tr("アガリやめで終了")
        case .completedAllRounds, nil: return tr("%@終了", model.gameLength.title)
        }
    }

    var gameResultCard: some View {
        VStack(spacing: 10) {
            Text(gameResultTitle)
                .scaledFont(22, weight: .black, design: .rounded)
                .foregroundStyle(Theme.coralText)
            if let place = model.playerPlace {
                Text(tr("あなたは %@", Self.placeText(place)))
                    .scaledFont(18, weight: .black, design: .rounded)
                    .foregroundStyle(Theme.ink)
            }
            VStack(spacing: 4) {
                ForEach(Array(model.ranking.enumerated()), id: \.offset) { place, player in
                    HStack {
                        Text(Self.placeText(place))
                            .scaledFont(13, weight: .black, design: .rounded)
                            .foregroundStyle(Theme.coralText)
                            .frame(width: 36, alignment: .leading)
                        Text(model.playerName(player))
                            .scaledFont(13, weight: .bold, design: .rounded)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(Self.pointsText(model.scores[player]))
                            .scaledFont(13, weight: .black, design: .rounded)
                            .foregroundStyle(Theme.inkSubText)
                    }
                }
            }
            RecordLabel(model.recordResult)
            if model.canReviveAfterBust { reviveButton }
            if model.canExtendAfterLastPlace { extendButton }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 会長指摘「誰が誰に点を振り込んだかわかるようにしてほしい」への対応。`pointChanges` で
    /// 全員ぶんの増減を出す。ツモのように払う人が複数いるケースも、タイトルの矢印1本では
    /// 表せないのでここで一覧にして補う。
    private var scoreTable: some View {
        VStack(spacing: 4) {
            ForEach(0..<MahjongModel.playerCount, id: \.self) { player in
                HStack {
                    Text(model.playerName(player))
                        .scaledFont(12, weight: .semibold, design: .rounded)
                        .foregroundStyle(Theme.inkSubText)
                    if let result = model.handResult, result.kind == .exhaustiveDraw {
                        drawStatus(player: player, result: result)
                    }
                    Spacer()
                    if let change = model.handResult?.pointChanges[player], change != 0 {
                        Text(change > 0 ? "+\(change)" : "\(change)")
                            .scaledFont(12, weight: .bold, design: .rounded)
                            .foregroundStyle(change > 0 ? Theme.tealText : Theme.coralText)
                            .fixedSize()
                    }
                    Text(Self.pointsText(model.scores[player]))
                        .scaledFont(12, weight: .black, design: .rounded)
                        .foregroundStyle(model.scores[player] < 0 ? Theme.coralText : Theme.ink)
                        // 英語（"25000 pts"）は日本語より長く、幅が固定の欄に 1 行で収める。
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: 66, alignment: .trailing)
                }
            }
        }
        .padding(.top, 4)
    }

    /// 流局の各家の札（テンパイ／ノーテン）と、テンパイの家の待ち牌（小さく。#2872）。
    private func drawStatus(player: Int, result: MahjongHandResult) -> some View {
        let isTenpai = result.tenpaiPlayers.contains(player)
        let waits = isTenpai ? MahjongShanten.waits(model.hands[player], meldCount: model.melds[player].count) : []
        // 9 面待ちでも iPhone SE の行（増減・持ち点と並ぶ）に収まるよう、多いときは小さくする
        let tileWidth: CGFloat = waits.count > 6 ? 8 : 10
        let label = isTenpai ? tr("テンパイ") : tr("ノーテン")
        return HStack(spacing: 4) {
            Text(label)
                .scaledFont(10, weight: .black, design: .rounded)
                .foregroundStyle(isTenpai ? Theme.tealText : Theme.inkSubText)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(Capsule().strokeBorder(isTenpai ? Theme.tealText : Theme.inkSub, lineWidth: 1))
                .fixedSize()
            if !waits.isEmpty {
                HStack(spacing: 1) {
                    ForEach(Array(waits.enumerated()), id: \.offset) { _, tile in
                        MahjongTileView(tile: tile, width: tileWidth, height: tileWidth * 1.4)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            waits.isEmpty
                ? label
                : tr("%1$@。待ち牌: %2$@", label, waits.map(\.displayName).joined(separator: MahjongAccessibility.listSeparator))
        )
    }

    // MARK: - 表示用の文言（#2166）

    /// 流局の罰符の内訳 1 行（#2872）。テンパイが 0 人・4 人なら点は動かない。それ以外は 3000 点を
    /// テンパイの家で分け合ってノーテンの家が払うので、1 人あたりの増減を出す。
    static func drawPenaltyLine(_ result: MahjongHandResult) -> String {
        let count = result.tenpaiPlayers.count
        if count == 0 { return tr("全員ノーテンです") }
        if count >= MahjongModel.playerCount { return tr("全員テンパイです") }
        let gain = result.tenpaiPlayers.first.map { result.pointChanges[$0] } ?? 0
        let loss = (0..<MahjongModel.playerCount).first { !result.tenpaiPlayers.contains($0) }
            .map { -result.pointChanges[$0] } ?? 0
        return tr("ノーテン罰符（テンパイ +%1$lld点・ノーテン -%2$lld点）", gain, loss)
    }

    /// 「3飜 30符 満貫」の行。満貫以上の呼び名は保存値（日本語）なので表示言語に直して添える。
    static func hanFuLine(_ result: MahjongHandResult) -> String {
        let fu = result.fu > 0 ? tr("%lld符", result.fu) + " " : ""
        let limit = result.limitName.map(MahjongHandResult.displayLimitName) ?? ""
        return tr("%lld飜", result.han) + " " + fu + limit
    }

    static func pointsText(_ points: Int) -> String {
        tr("%lld点", points)
    }

    /// 順位（0 始まり）の表記。英語は序数（1st・2nd…）なので、四人打ちの 4 位までは個別の文言にする。
    static func placeText(_ place: Int) -> String {
        switch place {
        case 0:  return tr("1位")
        case 1:  return tr("2位")
        case 2:  return tr("3位")
        case 3:  return tr("4位")
        default: return tr("%lld位", place + 1)
        }
    }
}
