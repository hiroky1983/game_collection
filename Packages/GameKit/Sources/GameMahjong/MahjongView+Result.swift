import SwiftUI
import Core
import MahjongTiles

extension MahjongView {
    // MARK: - リザルト

    var handResultCard: some View {
        VStack(spacing: 8) {
            Text(handResultTitle)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Theme.coral)
            if let result = model.handResult, result.kind != .exhaustiveDraw {
                Text("\(result.han)飜 \(result.fu > 0 ? "\(result.fu)符 " : "")\(result.limitName ?? "")")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                VStack(spacing: 3) {
                    ForEach(Array(result.yaku.enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.inkSub)
                    }
                }
                Text("\(result.gainedPoints)点")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.teal)
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
                Text(
                    result.tenpaiPlayers.isEmpty
                        ? "全員ノーテンです"
                        : "聴牌: " + result.tenpaiPlayers.map { model.playerName($0) }.joined(separator: "・")
                )
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
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
            "和了した手: "
                + sorted.map(\.displayName).joined(separator: "、")
                + "、和了牌は \(winningTile.displayName)"
        )
    }

    /// 立直で和了ったときだけ開示する裏ドラ表示牌（#351）。卓中央のドラ表示と同じ牌サイズ。
    private func uraDoraRow(_ tiles: [MahjongTile]) -> some View {
        HStack(spacing: 4) {
            Text("裏ドラ")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                MahjongTileView(tile: tile, width: 14, height: 19)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("裏ドラ表示牌: " + tiles.map(\.displayName).joined(separator: "、"))
    }

    /// 会長指摘「誰が誰に点を振り込んだかわかるようにしてほしい」への対応。ロンは放銃した人が
    /// 一意に決まるので、タイトルに「{放銃した人} → {和了した人}」を添える。ツモは複数人が
    /// 別々の額を払うため、単一の矢印では表せない。下の `scoreTable` 側で全員の点数の動きを
    /// 一覧できるようにして補う。
    private var handResultTitle: String {
        guard let result = model.handResult else { return "" }
        let winnerName = model.playerName(result.winner ?? 0)
        switch result.kind {
        case .exhaustiveDraw: return "流局"
        case .tsumo:  return "\(winnerName)のツモ"
        case .ron:
            guard let loser = result.loser else { return "\(winnerName)のロン" }
            return "\(model.playerName(loser)) → \(winnerName)のロン"
        }
    }

    /// 終わり方は3種類あり、東2局で突然終わっても理由が読めるよう見出しを分ける（#352）。
    /// 打ち切りの見出しは対局の長さで変える（#639。一局戦で「東風戦終了」と出ると嘘になる）。
    private var gameResultTitle: String {
        switch model.gameEndReason {
        case .busted:    return "トビで終了"
        case .agariYame: return "アガリやめで終了"
        case .completedAllRounds, nil: return "\(model.gameLength.title)終了"
        }
    }

    var gameResultCard: some View {
        VStack(spacing: 10) {
            Text(gameResultTitle)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Theme.coral)
            if let place = model.playerPlace {
                Text("あなたは \(place + 1)位")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            VStack(spacing: 4) {
                ForEach(Array(model.ranking.enumerated()), id: \.offset) { place, player in
                    HStack {
                        Text("\(place + 1)位")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.coral)
                            .frame(width: 36, alignment: .leading)
                        Text(model.playerName(player))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(model.scores[player])点")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.inkSub)
                    }
                }
            }
            RecordLabel(model.recordResult)
            if model.canReviveAfterBust { reviveButton }
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
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                    Spacer()
                    if let change = model.handResult?.pointChanges[player], change != 0 {
                        Text(change > 0 ? "+\(change)" : "\(change)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(change > 0 ? Theme.teal : Theme.coral)
                    }
                    Text("\(model.scores[player])点")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(model.scores[player] < 0 ? Theme.coral : Theme.ink)
                        .frame(width: 66, alignment: .trailing)
                }
            }
        }
        .padding(.top, 4)
    }
}
