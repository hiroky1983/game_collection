import SwiftUI
import Core
import MahjongTiles

/// 副露（鳴いた面子）の並び。手牌の外に晒すものなので、手牌とは別の行に置く。
///
/// 実物の麻雀は「鳴いた相手の方向へ牌を横向きにする」が、画面上の 13〜24pt の牌では
/// 向きの違いが読み取れないため、代わりに種類（ポン / チー / カン）を小さく添える。
struct MahjongMeldRow: View {
    let melds: [MahjongCall]
    let tileWidth: CGFloat
    /// 種類の見出しを出すか（他家の小さい表示では省く）。
    var showsBadge: Bool = true
    /// 指定すると、1つの副露の牌をこの枚数ごとに折り返し、複数の副露は横に並べず縦に積む。
    /// 上家・下家の狭い列で牌のサイズを河と揃えたところ、ポン(3枚)やカン(4枚)が横一列のままだと
    /// 河のグリッド（2列）の幅を超えてはみ出し、隣の要素と重なって見えていた（会長指摘）。
    /// 河と同じ列数で折り返せば、幅が河のグリッドを超えることが構造的に無くなる。
    var maxTilesPerRow: Int?

    var body: some View {
        // 中央寄せ（河のグリッドが中央寄せなので、左寄せだと副露だけズレて散らかって見える）。
        if !melds.isEmpty {
            if let maxTilesPerRow {
                // 1組=1行にせず、上限枚数まで複数の副露を同じ行に詰める（ポン3枚+カン4枚=7枚が
                // ちょうど1行）。組ごとに行を分けると、副露が多い終盤に縦へ伸びて河を圧迫する。
                VStack(alignment: .center, spacing: 1) {
                    ForEach(Array(Self.packRows(melds, perRow: maxTilesPerRow).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 3) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, meld in
                                HStack(spacing: 1) {
                                    ForEach(Array(meld.tiles.enumerated()), id: \.offset) { _, tile in
                                        MahjongTileView(tile: tile, width: tileWidth, height: tileWidth * 1.34)
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(MahjongAccessibility.meldLabel(meld))
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(melds.enumerated()), id: \.offset) { _, meld in
                        singleRowMeld(meld)
                    }
                }
            }
        }
    }

    /// 副露を、1行あたりの牌の枚数が `perRow` を超えないように前から詰めて行に分ける。
    /// 1組（最大4枚）は行をまたがない。
    static func packRows(_ melds: [MahjongCall], perRow: Int) -> [[MahjongCall]] {
        var rows: [[MahjongCall]] = []
        var current: [MahjongCall] = []
        var count = 0
        for meld in melds {
            let n = meld.tiles.count
            if !current.isEmpty && count + n > perRow {
                rows.append(current)
                current = []
                count = 0
            }
            current.append(meld)
            count += n
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private func singleRowMeld(_ meld: MahjongCall) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                ForEach(Array(meld.tiles.enumerated()), id: \.offset) { _, tile in
                    MahjongTileView(tile: tile, width: tileWidth, height: tileWidth * 1.34)
                }
            }
            if showsBadge {
                Text(Self.badge(meld))
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MahjongAccessibility.meldLabel(meld))
    }

    static func badge(_ meld: MahjongCall) -> String {
        switch meld.kind {
        case .pon:       return "ポン"
        case .chi:       return "チー"
        case .openKan:   return "カン"
        case .addedKan:  return "加槓"
        case .closedKan: return "暗槓"
        }
    }
}

/// 鳴くかスルーかを選ぶ操作列。
struct MahjongCallBar: View {
    let offer: MahjongModel.CallOffer
    let onAccept: (MahjongCall) -> Void
    let onDecline: () -> Void

    /// 1 行に並べるボタンの上限。チーの取り方が 3 通り + スルーで 4 つになるのが現実的な上限で、
    /// iPhone SE（画面 375pt）でもここまでは 1 行に収まる。これ以上（カンとポンも同時に鳴ける形）は
    /// 折り返す。**縦に積むと画面から溢れて上下が切れる**ので、`.adaptive` ではなく列数を明示する。
    private static let maximumColumns = 4
    // 会長再指摘: 見出し行（牌＋「が出ました」）自体が対局中の1行ボタン行との差を生んでいた。
    // 見出しを独立した行にせず、牌をボタン行の左に**同じ行で**並べて行数そのものを揃える。
    private static let buttonHeight: CGFloat = 40

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            MahjongTileView(tile: offer.tile, width: 18, height: 24)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(offer.tile.displayName)が出ました。鳴きますか")
            // 選択肢はチーの取り方違いで最大 3 つ増える（カン + ポン + チー3通り + スルーで 6 つ）。
            // 縦に積むと iPhone SE では画面からはみ出すので、入る数だけ横に並べて折り返す。
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(offer.options.enumerated()), id: \.offset) { _, option in
                    callButton(option)
                }
                Button(action: onDecline) {
                    // 4列（チー3択+スルー）まで並ぶと1列がかなり狭くなり、`lineLimit(1)` だと
                    // `minimumScaleFactor` を下げても「ス…」と省略され続けた。1行に収める
                    // こと自体を諦め、必要なら2行に折り返させて省略記号そのものを起こさせない。
                    Text("スルー")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                // 会長指摘「ひどい」: `.controlSize(.small)` だけだとボタンの既定の丸みが強く、
                // 幅に対して高さが近いとき（チーが3択でボタンが狭いとき）円に見えてしまっていた。
                // 角丸の四角形だと明示して、幅・高さの比に関わらず同じ見た目にする。
                .buttonBorderShape(.roundedRectangle(radius: 8))
                .tint(Theme.fillMuted)
                .accessibilityLabel("鳴かずに進める")
            }
            // 会長再々指摘（2026-08-29「文言が…になる」）の真因: `.frame(maxWidth:)` を
            // HStack の外に付けても**外枠が広がるだけ**で、中の LazyVGrid には理想幅
            // （列の最小幅）しか提案されず、ボタンが狭いまま中央に固まっていた。
            // グリッド自身に付けて、余り幅がそのまま列幅の提案として届くようにする。
            .frame(maxWidth: .infinity)
        }
        // 会長指摘: カードが画面幅いっぱいに広がらず、ボタンが狭まって「スルー」が省略されていた。
        // 他のアクション行（立直・ツモ等）と同じく幅いっぱいに広げる。
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 鳴きの選択肢 +「スルー」をちょうど収める列。数が少ないときに右側が空かないよう、
    /// ボタンの数だけ等幅の列を作る。
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: min(offer.options.count + 1, Self.maximumColumns)
        )
    }

    private func callButton(_ option: MahjongCall) -> some View {
        // 同じ種類の鳴きが複数あるとき（チーの取り方違い）だけ、手牌から使う牌を絵で添える。
        // 「萬子の3・萬子の4」という読み上げ用の文をそのまま出すと、この幅では潰れて読めない。
        let needsDetail = offer.options.filter { $0.kind == option.kind }.count > 1
        return Button { onAccept(option) } label: {
            // 会長指摘（2026-08-29）: 選択肢が多く列幅が狭いとき、文字＋牌の横並びでは
            // 固定幅の牌に文字が押し潰されて「…」になっていた。文字は `fixedSize` で
            // **絶対に省略させず**、横に入り切らないときだけ牌を下段に落とす。
            // 縦積みでも円に見えないことは `.roundedRectangle` の明示で担保済み（下）。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 3) {
                    callButtonText(option)
                    if needsDetail { detailTiles(option) }
                }
                VStack(spacing: 1) {
                    callButtonText(option)
                    if needsDetail { detailTiles(option) }
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .tint(option.isKan ? Theme.purple : Theme.coral)
        .accessibilityLabel(MahjongAccessibility.callOptionLabel(option))
    }

    /// ボタンの文言。`fixedSize` で縮小も省略もさせない（潰すのは牌の側・上のコメント参照）。
    private func callButtonText(_ option: MahjongCall) -> some View {
        Text(option.actionName)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .fixedSize()
    }

    /// 手牌から使う牌の添え絵（チーの取り方違いの区別用）。
    private func detailTiles(_ option: MahjongCall) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(option.tilesFromHand.enumerated()), id: \.offset) { _, tile in
                MahjongTileView(tile: tile, width: 10, height: 14)
            }
        }
    }
}

/// 自分の手番でのカン（暗槓・加槓）ボタン。候補が複数あるときはメニューで選ばせる。
struct MahjongKanButton: View {
    let options: [MahjongCall]
    let onSelect: (MahjongCall) -> Void

    var body: some View {
        if options.count > 1 {
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button("\(MahjongMeldRow.badge(option)) \(option.tile.displayName)") {
                        onSelect(option)
                    }
                }
            } label: {
                label
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.purple)
            .accessibilityLabel("カンする牌を選ぶ")
        } else {
            Button {
                if let option = options.first { onSelect(option) }
            } label: {
                label
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.purple)
            .disabled(options.isEmpty)
            .accessibilityLabel(options.first.map(MahjongAccessibility.callOptionLabel) ?? "カン")
        }
    }

    private var label: some View {
        Text("カン")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 40)
    }
}
