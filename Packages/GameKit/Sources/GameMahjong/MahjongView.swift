import SwiftUI
import Core
import MahjongTiles

public struct MahjongView: View {
    @State private var model: MahjongModel
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss
    @State private var showStartSheet = true
    /// 誤タップ防止: 1タップ目は選択（浮かせる演出）だけ、同じ牌をもう1回タップしたら実際に切る。
    /// 複数枚ある牌を区別できるよう `stableHandIDs` の合成ID（牌の値＋出現順）で管理する。
    @State private var selectedTileID: String?

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: MahjongModel(services: services))
        _showStartSheet = State(initialValue: !services.snapshots.exists(for: "mahjong4"))
    }

    public var body: some View {
        VStack(spacing: 6) {
            statusBar
            // 卓（対面・上家・下家の河 + 自分の河）は局の決着後もそのまま見えている方が自然なので、
            // 局面/リザルトの分岐の外に置く（実物の卓も清算が終わるまで牌は残ったまま）。
            // layoutPriority(1) は将棋の盤（ShogiView.board）と同じ考え方: 卓を優先して
            // 高さを確保させ、他の要素（手牌・アクション行・バナー）がそのぶん譲る。
            // これが無いと卓が伸び放題になり、画面下のバナー広告が画面外へ押し出されて
            // 見えなくなる／レイヤーが崩れて見える（会長のシミュレータ確認で発覚）。
            mahjongTable
                .layoutPriority(1)
            if model.phase == .gameResult {
                gameResultCard.transition(.opacity)
                Spacer(minLength: 0)
            } else if model.phase == .handResult {
                handResultCard.transition(.opacity)
                Spacer(minLength: 0)
            } else {
                handOnTable.transition(.opacity)
            }
            // 会長指摘: リザルト画面でも「切る牌をタップしよう」が出ていて、打牌できない場面なのに
            // 打牌を促す文言が残っていた。対局中だけ出す。
            if isInPlay {
                HowToPlayHint(.mahjong, playLog: services.playLog)
            }
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .gameResult)
            BannerSlot(ads: services.ads)
        }
        // 局面 → リザルトの差し替えは、入れ替わる枝ではなく残り続ける親に置く（#195）。
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        .padding(Theme.pad)
        .popBackground()
        .reviewRequestPrompt(services.review)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        #endif
        .tint(Theme.coral)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Label("戻る", systemImage: "chevron.left") }
            }
            ToolbarItem(placement: .principal) {
                Text("麻雀")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
        }
        // 役と点数は 3 行に収まらないので「くわしいルール」へ送る（#118）。
        .howToPlay(.mahjong) { MahjongRuleSheet() }
        .sheet(isPresented: $showStartSheet) {
            MahjongStartSheet {
                showStartSheet = false
                model.startGame()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .interactiveDismissDisabled(true)
        }
        .task {
            // 中断から戻ったときに手番が止まったままにならないようにする。
            await model.runCPUTurnsIfNeeded()
        }
        .task(id: model.turnKey) {
            await model.runCPUTurnsIfNeeded()
        }
        .onChange(of: model.playerHand) {
            // 手牌が変わったら選択（誤タップ防止の1タップ目）は必ず解除する。
            selectedTileID = nil
        }
        .onChange(of: model.currentPlayer) {
            selectedTileID = nil
        }
    }

    // MARK: - ステータス

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text("東\(model.roundNumber)局")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Theme.ink)
            if model.honba > 0 {
                Text("\(model.honba)本場")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
            }
            if model.riichiSticks > 0 {
                Label("\(model.riichiSticks)", systemImage: "flag.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.coral)
            }
            Spacer()
            if let dora = model.doraIndicators.first {
                HStack(spacing: 3) {
                    Text("ドラ")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                    MahjongTileView(tile: dora, width: 18, height: 24)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("ドラ表示牌は\(dora.displayName)")
            }
            Text("残り\(model.remainingTiles)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            MahjongAccessibility.roundLabel(
                roundNumber: model.roundNumber, honba: model.honba, remainingTiles: model.remainingTiles
            )
        )
    }

    // MARK: - 雀卓

    /// 河（捨て牌）は全員共通のサイズにする（会長指摘「大きさはユーザー含め均一に」）。
    private static let discardPerRow = 6
    // 会長指摘: 3列に増えると自分のセクション（チップ＋河＋手牌一覧）の高さが伸びて
    // 手牌一覧側に食い込む・卓の角丸でクリップされる、という不具合につながっていた。
    // 常に2列（12枚）までに固定し、それより古い牌は落とす（`discardStrip` 側で
    // `tiles.suffix(maxTiles)` により新しい方を残す実装になっている）。
    private static let discardMaxTiles = 12
    /// 左右の家は縦に細い帯で見せる分、表示枚数と1行あたりの枚数を絞って卓の高さに収める。
    private static let sideDiscardPerRow = 2
    private static let sideDiscardMaxTiles = 8
    private static let discardRowSpacing: CGFloat = 2
    private static let discardTileAspect: CGFloat = 1.34
    private static let discardTileWidthDivisor: CGFloat = 19
    private static let tablePadding: CGFloat = 10

    private static func discardTileWidth(forTableSide side: CGFloat) -> CGFloat {
        max(10, side / discardTileWidthDivisor)
    }

    /// 緑の卓に、実物と同じ席の位置関係（自分=下・下家=右・対面=上・上家=左）で
    /// 各家の河（捨て牌）を配置する。会長フィードバック「普通に雀卓のUIにしてほしい」「正方形にしてほしい」
    /// に対応。手番の順は 0(自分)→1(右)→2(対面)→3(左) で、これは実物の反時計回りの席順そのもの。
    /// `GeometryReader` + `aspectRatio(1, contentMode: .fit)` は将棋の盤（`ShogiView.board`）と
    /// 同じ手法: 利用可能な高さを超えないぶんの正方形に自動で収まる。
    ///
    /// 以前は `ZStack` + `position()` で卓の四辺に絶対座標を与えていたが、河が3段に増えたり
    /// リーチで名前チップが伸びたりすると、固定の高さ・幅の枠に収まらず**中央パネルや反対側の
    /// チップに重なって文字が読めなくなる**不具合が繰り返し出た（会長指摘）。絶対座標は要素どうしの
    /// 重なりを構造的に防げないため、`VStack`/`HStack` の自動フローに置き換える。Stack は子を
    /// 順番に並べるだけなので、河が増えて背が高くなっても・チップが伸びても**隣の要素を押しのける
    /// だけで重ならない**。
    private var mahjongTable: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let tileWidth = Self.discardTileWidth(forTableSide: side)
            let contentWidth = side - Self.tablePadding * 2
            VStack(spacing: 6) {
                opponentRow(2, tileWidth: tileWidth) // 対面
                Spacer(minLength: 2)
                HStack(alignment: .center, spacing: 4) {
                    opponentColumn(3, tileWidth: tileWidth) // 上家（左）
                    Spacer(minLength: 2)
                    // 会長指摘「卓上にもUIが欲しい」への対応: 卓の中央がただの空き地だったので、
                    // 実物の卓中央（点棒・ドラ表示・残り枚数が集まる場所）にならって小さな盤面を置く。
                    tableCenterPanel
                    Spacer(minLength: 2)
                    opponentColumn(1, tileWidth: tileWidth) // 下家（右）
                }
                Spacer(minLength: 2)
                playerDiscardOnTable(tileWidth: tileWidth, overviewWidth: contentWidth - 12) // 自分
            }
            .padding(Self.tablePadding)
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x2E7A50), Color(hex: 0x1D5638)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                            .strokeBorder(Color(hex: 0x123726), lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            )
            // 河が伸びきってなお収まらない極端なケースでも、白背景側へにじみ出さず
            // 卓の角丸の内側でだけ収まるようにする（重なりよりましな失敗のさせ方）。
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .frame(width: geo.size.width, height: geo.size.height)
            // 河のアニメーションが止まらないという指摘のため、原因を特定しきれないまま
            // 力技で対処する: 卓の中身への暗黙アニメーションを一切禁止する。牌の増減・並び替えは
            // すべて瞬時に反映されるだけになる（実物の牌もアニメーションはしない）。
            .transaction { $0.animation = nil }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// 卓中央パネル。実物の卓中央（点棒・ドラ表示・残り枚数が集まる場所）を模した小さな盤面。
    /// 情報は `statusBar` と重複するので、読み上げは `statusBar` 側に任せる（`accessibilityHidden`）。
    ///
    /// 会長指摘: 左右のチップ（特にリーチで「立直」タグが付くと長くなる）が省略されて読めなく
    /// なっていた。卓の横幅は [左チップ][中央パネル][右チップ] の3つで奪い合っているので、
    /// 中央パネルを小さくするほど左右チップに幅が回る。ここの情報は `statusBar` と重複している
    /// ぶん、思い切って縮めても実害が無い。
    private var tableCenterPanel: some View {
        VStack(spacing: 3) {
            Text("東\(model.roundNumber)局\(model.honba > 0 ? " \(model.honba)本場" : "")")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let dora = model.doraIndicators.first {
                HStack(spacing: 3) {
                    Text("ドラ")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    MahjongTileView(tile: dora, width: 14, height: 19)
                }
            }
            Text("残り\(model.remainingTiles)枚")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.18)))
        .accessibilityHidden(true)
        // 左右チップを優先して幅を譲る（chip 側は最大 190pt まで伸びうる）が、
        // 完全に0まで削られると「東…」のように文字自体が省略されるので下限は死守する。
        .frame(minWidth: 60)
        .layoutPriority(-1)
    }

    /// チップ全体の最大幅。無制限に伸ばす `.fixedSize()` だと、長い名前・大きい点数・「立直」
    /// タグが重なったときに中央パネルや反対側のチップへ食い込んで文字が重なって読めなくなった
    /// （会長指摘）。上限を決めて、それを超える分は文字を縮小させる方に倒す。
    private static let chipMaxWidth: CGFloat = 190

    /// 会長指摘「上下は横長・左右は2列でUIがキモい」への対応: 4 席すべて同じ横一列のチップに
    /// 統一する。リーチは別の小さなカプセルを浮かせるのではなく、**同じチップの中**で
    /// 縁取りを付け、末尾に「立直」タグを添える形にして「セクションの中でわかる」ようにする。
    private func opponentNameChip(_ index: Int, icon: String = "cpu") -> some View {
        let isCurrent = model.currentPlayer == index && model.phase == .playing
        let isRiichi = model.riichi[index]
        return VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isCurrent ? Theme.coral : Theme.Fixed.ink.opacity(0.6))
                Text("\(model.playerName(index))・\(Self.windNames[model.seatWind(index)])")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Fixed.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("\(model.scores[index])")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(model.scores[index] < 0 ? Theme.coral : Theme.Fixed.ink.opacity(0.7))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            // 会長指摘: 「立直」タグが名前・点数と同じ行で幅を取り合うと、リーチが入った瞬間に
            // 文字が縮んで見える。タグは行を分けて、名前・点数の行の幅取り合いに参加させない。
            if isRiichi {
                Text("立直")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.coral))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        // 会長指摘: リーチ中に背景を半透明の珊瑚色にしたら、緑の卓と混ざって文字が読みにくく
        // なった。塗りは常にはっきりした不透明の白のままにして、リーチは縁取り＋タグだけで示す。
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.92)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isRiichi ? Theme.coral : .clear, lineWidth: isRiichi ? 2 : 0)
        )
        .frame(maxWidth: Self.chipMaxWidth)
    }

    /// 対局中（決着していない）か。会長指摘: リザルト画面ではリザルトカードの得点表が
    /// 全員ぶんの名前・点数・増減をすでに示しているので、卓の上の名前チップは4席とも
    /// 完全に冗長。加えて、リザルトカードが伸びるぶん卓自体（`mahjongTable`）が小さく
    /// 描かれ、チップの文字が入り切らず省略記号だけになる不具合も出ていた（会長のスクショで発覚）。
    /// 対局中だけ出す形にすれば、両方いっぺんに解消する。
    private var isInPlay: Bool {
        model.phase == .playing || model.phase == .ronOffer || model.phase == .callOffer
    }

    /// 対面（横一列の河）。
    private func opponentRow(_ index: Int, tileWidth: CGFloat) -> some View {
        VStack(spacing: 3) {
            if isInPlay {
                opponentNameChip(index)
            }
            // 会長指摘: 固定10ptだと河の牌より露骨に小さく、間隔が詰まって重なって見えていた。
            // 河と同じ動的な `tileWidth` を使い、大きさを揃える。
            MahjongMeldRow(melds: model.melds[index], tileWidth: tileWidth, showsBadge: false)
            discardStrip(model.discards[index], tileWidth: tileWidth, perRow: Self.discardPerRow, maxTiles: Self.discardMaxTiles)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(opponentAccessibilityLabel(index))
    }

    /// 副露1組の最大枚数（暗槓・加槓）に合わせた、上家・下家の副露の折り返し列数。
    /// 河の2列幅のまま1行2枚で折り返すと、3〜4枚ある副露が1組あたり2行になり、
    /// 副露が最大4組（手牌の構造上の上限）並ぶと最大8行分の高さになって、下に置く
    /// 捨て牌欄を押しのけて見えなくしていた（会長指摘の実戦画面: 捨て牌が追えず覚えゲーになる）。
    /// 1行4枚まで並べれば1組4枚のカンでも必ず1行に収まり、副露の高さは
    /// 「組数（最大4）」行を超えなくなる。牌の幅は河のグリッドと同じ全体幅に収まるよう、
    /// 河の列数(2)ぶんの幅をこちらの列数(4)で割った分だけ縮める。
    private static let sideMeldPerRow = 4

    /// 上家・下家（縦に細い帯の河。回転はさせない）。チップは対面・自分と同じ `opponentNameChip`。
    private func opponentColumn(_ index: Int, tileWidth: CGFloat) -> some View {
        let meldTileWidth = tileWidth * CGFloat(Self.sideDiscardPerRow) / CGFloat(Self.sideMeldPerRow)
        return VStack(spacing: 3) {
            if isInPlay {
                opponentNameChip(index)
            }
            MahjongMeldRow(
                melds: model.melds[index], tileWidth: meldTileWidth,
                showsBadge: false, maxTilesPerRow: Self.sideMeldPerRow
            )
            discardStrip(
                model.discards[index], tileWidth: tileWidth,
                perRow: Self.sideDiscardPerRow, maxTiles: Self.sideDiscardMaxTiles
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(opponentAccessibilityLabel(index))
    }

    private func opponentAccessibilityLabel(_ index: Int) -> String {
        let isCurrent = model.currentPlayer == index && model.phase == .playing
        return MahjongAccessibility.playerLabel(
            name: model.playerName(index), score: model.scores[index],
            isRiichi: model.riichi[index], isCurrent: isCurrent, melds: model.melds[index]
        )
        + "。"
        + MahjongAccessibility.discardPileLabel(
            player: model.playerName(index), tiles: model.discards[index]
        )
    }

    /// 河を小さい牌で並べる。古い牌から順に、入りきらないぶんは新しい側を残す。
    /// 会長指摘: 卓の中心寄せにしたい。中央寄せだと最終行の枚数が変わるたびに既に置いた牌の
    /// 位置がずれるが、卓全体でアニメーションを止めている（`transaction { $0.animation = nil }`）
    /// ため、ずれても瞬時に切り替わるだけでアニメーションはしない。
    private func discardStrip(
        _ tiles: [MahjongTile], tileWidth: CGFloat, perRow: Int, maxTiles: Int
    ) -> some View {
        let shown = Array(tiles.suffix(maxTiles))
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: Self.discardRowSpacing), count: perRow),
            alignment: .center,
            spacing: Self.discardRowSpacing
        ) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, tile in
                MahjongTileView(tile: tile, width: tileWidth, height: tileWidth * Self.discardTileAspect)
            }
        }
        .frame(minHeight: tileWidth * Self.discardTileAspect, alignment: .center)
    }

    // MARK: - 自分の河

    /// 会長指摘: 「あなたの河」という文字ラベルは不要。CPU と同じ表現（得点・東西南北）に揃える。
    /// `opponentNameChip` をそのまま流用し、アイコンだけ「あなた」向けに差し替える。
    ///
    /// 会長指摘（2026-08-25）: 卓の下部（`handOnTable`・横スクロール）はタップしやすい大きさの
    /// 操作用の補助セクションであって、「卓上に手牌を置け」の答えではなかった。卓の上＝この
    /// `playerDiscardOnTable`（緑の正方形の卓そのものの中）に、縮小してでも手牌14枚が一目で
    /// 見渡せる一覧を別途置く。
    private func playerDiscardOnTable(tileWidth: CGFloat, overviewWidth: CGFloat) -> some View {
        VStack(spacing: 4) {
            if isInPlay {
                opponentNameChip(MahjongModel.humanIndex, icon: "person.fill")
            }
            // 会長指摘「鳴いた牌は卓の上においてほしい」への対応: 対面・上家・下家は既に卓の上
            // （このVStackと同じ緑の正方形の中）に副露を出している。自分だけ卓の下（操作用の
            // `handOnTable`）にあったのを、同じ卓の上に揃える。
            MahjongMeldRow(melds: model.playerMelds, tileWidth: tileWidth, showsBadge: false)
            discardStrip(
                model.discards[MahjongModel.humanIndex],
                tileWidth: tileWidth, perRow: Self.discardPerRow, maxTiles: Self.discardMaxTiles
            )
            if isInPlay {
                handOverviewOnTable(width: overviewWidth)
            }
        }
        .frame(maxWidth: .infinity)
        // 河のアニメーションが「ルーレット」化する一因だったため、ここでは明示的に付けない
        // （卓全体は既に `.transaction { $0.animation = nil }` で無効化している）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            MahjongAccessibility.discardPileLabel(
                player: "あなた", tiles: model.discards[MahjongModel.humanIndex]
            )
        )
    }

    private static let handOverviewSpacing: CGFloat = 2
    private static let handOverviewMaxTileWidth: CGFloat = 22
    private static let handOverviewAspect: CGFloat = Self.tableHandTileHeight / Self.tableHandTileWidth

    /// 卓の上（緑の正方形の中）に置く、手牌14枚を縮小して一目で見渡せる一覧。
    /// タップ操作は卓下部の `handOnTable`（大きい牌・横スクロール）が担うので、こちらは
    /// 視認性だけが目的の非インタラクティブな一覧にする（読み上げも下部側に一本化）。
    private func handOverviewOnTable(width: CGFloat) -> some View {
        let hand = model.playerHand.tiles
        let drawn = model.playerDrawnTile
        let tileCount = hand.count + (drawn != nil ? 1 : 0)
        let totalSpacing = Self.handOverviewSpacing * CGFloat(max(0, tileCount - 1))
        let rawWidth = tileCount > 0
            ? (width - totalSpacing) / CGFloat(tileCount) : Self.handOverviewMaxTileWidth
        let tileWidth = max(10, min(Self.handOverviewMaxTileWidth, rawWidth))
        let tileHeight = tileWidth * Self.handOverviewAspect
        return HStack(spacing: Self.handOverviewSpacing) {
            ForEach(Array(hand.enumerated()), id: \.offset) { _, tile in
                MahjongTileView(tile: tile, width: tileWidth, height: tileHeight)
            }
            if let drawn {
                MahjongTileView(tile: drawn, width: tileWidth, height: tileHeight, isHinted: true)
            }
        }
        .frame(width: width, alignment: .center)
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }

    // MARK: - 手牌

    /// 会長指摘「持ち牌もグリーンの卓の上に一列に並べて見てほしい」「横スクロールは維持して」への対応。
    /// 以前の 7列×2段の白カードをやめ、卓と同じ緑フェルトの帯に単列（横スクロール）で並べる。
    /// 名前・風・点数は自分の河側（`playerDiscardOnTable`）のチップに一本化したので、ここでは持たない。
    ///
    /// **「ルーレット現象」の正体**（Fable・Opus の並行調査で特定）: アニメーションでも
    /// ScrollView でもなく、**CPU のツモ牌が自分の手牌14枚目として表示されるデータバグ**だった。
    /// `model.drawnTile` は全員共有のプロパティ（`draw(for:)` が誰の手番でも同じ変数へ書く）で、
    /// CPU の手番中（1人あたり `cpuDelay` ≒520ms）も値が入れ替わり続ける。ここを手番の判定なしに
    /// 描いていたため、自分が1枚切るたびに右端の枠が CPU1→CPU2→CPU3 のツモ牌へパタパタと
    /// 4回連続で切り替わって見えていた。これは本物のデータ変化なので、`transaction { animation
    /// = nil }` でも identity 安定化でも ScrollView の有無でも止まらなかった
    /// （過去の対策が軒並み効かなかった理由）。`MahjongModel.playerDrawnTile` で自分の手番以外は
    /// nil を返すようにして解消した。
    private static let tableHandTileWidth: CGFloat = 34
    private static let tableHandTileHeight: CGFloat = 46
    private static let tableHandSpacing: CGFloat = 3
    private static let tableHandDrawnGap: CGFloat = 8
    /// 選択時に牌を -10pt 持ち上げる演出が ScrollView の上端で切れないための余白。
    private static let tableHandLift: CGFloat = 12

    private var handOnTable: some View {
        // 切れる牌の判定は手牌の枚数ぶん走るので、1 回だけ求めて配る（#190 と同じ考え方）。
        let discardable = model.discardableTiles
        let waits = model.playerWaits
        // model.playerHand.tiles を直接使う（常にソート済み）。以前は差分適用のローカル state を
        // 挟んでいたが、末尾に追加するだけだとソート順が崩れて「並び替えが効かない」不具合になった。
        let hand = model.playerHand.tiles
        let drawn = model.playerDrawnTile
        return VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.tableHandSpacing) {
                    // identity は **配列の位置**（`\.offset`）にする。牌の値を identity にすると、
                    // 途中の1枚が抜けて別の牌が別の位置に挿さったとき「生き残った牌が別スロットへ
                    // 移動した」と SwiftUI に解釈され、横滑りを補間できる状態になってしまう
                    // （Opus 指摘）。手牌は毎回ゼロから並べ直す配列なので、位置 identity にすれば
                    // 各スロットは「同じ View の中身が差し替わるだけ」になり、動きようがない。
                    ForEach(Array(hand.enumerated()), id: \.offset) { index, tile in
                        handTile(tile, id: "hand\(index)", isDrawn: false, discardable: discardable)
                    }
                    Spacer().frame(width: Self.tableHandDrawnGap)
                    // ツモ牌が無い間も同じ幅の透明プレースホルダーを置き、コンテンツの総幅を
                    // 常に一定に保つ。ツモ牌の出入りで ScrollView の contentSize が変わると
                    // UIScrollView 側がスクロール位置を自前で補正することがあるため、幅そのものを
                    // 固定してその発火条件自体を無くす。
                    ZStack {
                        Color.clear
                        if let drawn {
                            handTile(drawn, id: "drawn", isDrawn: true, discardable: discardable)
                        }
                    }
                    .frame(width: Self.tableHandTileWidth, height: Self.tableHandTileHeight)
                }
                .padding(.horizontal, 6)
                .padding(.top, Self.tableHandLift)
                .padding(.bottom, 6)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .defaultScrollAnchor(.leading)
            .frame(height: Self.tableHandTileHeight + Self.tableHandLift + 6)
            // 並び替え・出し入れは瞬時に反映するだけにする（雀卓側と同じ考え方）。
            // 選択（浮き上がり）演出は handTile 側で個別に `.animation` を付け直しているので、
            // ここで止めても影響しない。
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            // 副露は「卓の上においてほしい」（会長指摘）ため `playerDiscardOnTable` 側に移した。
            // ここ（操作用のスクロール行）には置かない。
            hintLine(waits: waits)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x2E7A50), Color(hex: 0x1D5638)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .strokeBorder(Color(hex: 0x123726), lineWidth: 3)
                )
        )
    }

    /// 会長指摘「誤タップ防止のため1タップでフォーカス、2タップ目で捨てる」への対応。
    /// 1回目のタップは選択（アウトライン＋浮き上がり）だけ。同じ牌をもう一度タップしたときだけ
    /// 実際に `model.discard` を呼ぶ。別の牌をタップした場合は選択を切り替えるだけで切らない。
    private func handTile(
        _ tile: MahjongTile, id: String, isDrawn: Bool, discardable: Set<MahjongTile>
    ) -> some View {
        let canDiscard = discardable.contains(tile)
        let isSelected = selectedTileID == id
        return MahjongTileView(
            tile: tile,
            width: Self.tableHandTileWidth,
            height: Self.tableHandTileHeight,
            isBlocked: model.isPlayerTurn && !canDiscard,
            isHinted: isDrawn
        )
        // 牌の絵柄そのものは、外側の選択アニメーションの影響を受けないようここで打ち切る
        // （無いと、選択解除と絵柄の差し替えが重なったときにクロスフェードして見える）。
        .transaction { $0.animation = nil }
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Theme.coral, lineWidth: isSelected ? 2.5 : 0)
        )
        .shadow(color: isSelected ? .black.opacity(0.3) : .clear, radius: isSelected ? 5 : 0, y: 3)
        .offset(y: isSelected ? -10 : 0)
        .gameAnimation(.spring(response: 0.22, dampingFraction: 0.7), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            guard model.isPlayerTurn, canDiscard else { return }
            if isSelected {
                // 選択解除と打牌を同じトランザクションにする。別々のフレームに分かれると
                // 「選択解除」→「手牌の入れ替え」の2段ジャンプに見えることがある（Opus指摘）。
                var transaction = Transaction()
                transaction.animation = nil
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selectedTileID = nil
                    model.discard(tile)
                }
            } else {
                selectedTileID = id
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            MahjongAccessibility.handTileLabel(tile, isDrawn: isDrawn, isDiscardable: canDiscard)
        )
        .accessibilityHint("ダブルタップでこの牌を切ります")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.discard(tile) }
        .disabled(!model.isPlayerTurn)
    }

    /// 手牌の下に出す 1 行の案内（#190 の設定に従う）。
    @ViewBuilder
    private func hintLine(waits: [MahjongTile]) -> some View {
        let message: String? = {
            if model.isDeclaringRiichi { return "立直します。切る牌を選んでください" }
            if model.isPlayerFuriten && !waits.isEmpty { return "フリテンです（ツモでのみ和了できます）" }
            if !waits.isEmpty {
                // ツモ牌を除いた 13 枚の待ちなので、条件つきの言い方にする（`playerWaits` を参照）。
                return "ツモ切りすると " + waits.map(\.displayName).joined(separator: "・") + " 待ち"
            }
            return nil
        }()
        if let message {
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(message)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(model.isPlayerFuriten ? Theme.inkSub : Theme.coral)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - リザルト

    private var handResultCard: some View {
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

    private var gameResultCard: some View {
        VStack(spacing: 10) {
            Text("東風戦終了")
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

    // MARK: - 操作

    /// 会長指摘: 鳴きの選択肢（`MahjongCallBar`）が出ると、それまでの1行ボタンより背が高いぶん
    /// このセクション自体の高さが変わり、下のバナー広告などが動いて見える。全ケースに共通の
    /// 最小高さを持たせて、差を小さくする（1行の鳴き提示ならほぼ動かなくなる）。
    private static let actionAreaMinHeight: CGFloat = 72

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .ronOffer:
            HStack(spacing: 12) {
                actionButton("見逃す", color: Theme.fillMuted) {
                    model.declineRon()
                    Task { await model.runCPUTurnsIfNeeded() }
                }
                actionButton("ロン", color: Theme.coral) { model.declareRon() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
            .frame(minHeight: Self.actionAreaMinHeight)
        case .callOffer:
            if let offer = model.callOffer {
                MahjongCallBar(
                    offer: offer,
                    onAccept: { call in
                        model.acceptCall(call)
                        Task { await model.runCPUTurnsIfNeeded() }
                    },
                    onDecline: {
                        model.declineCall()
                        Task { await model.runCPUTurnsIfNeeded() }
                    }
                )
                .frame(minHeight: Self.actionAreaMinHeight)
            }
        case .playing:
            HStack(spacing: 12) {
                if model.isDeclaringRiichi {
                    actionButton("やめる", color: Theme.fillMuted) { model.cancelRiichiDeclaration() }
                } else {
                    actionButton("立直", color: Theme.purple, disabled: !model.canDeclareRiichi) {
                        model.declareRiichi()
                    }
                }
                // カンは出来るときだけ出す（常設すると押せないボタンが 3 つ並ぶ）。
                if model.canDeclareKan {
                    MahjongKanButton(options: model.availableSelfKans) { call in
                        model.declareKan(call)
                        Task { await model.runCPUTurnsIfNeeded() }
                    }
                }
                actionButton("ツモ", color: Theme.coral, disabled: !model.canDeclareTsumo) {
                    model.declareTsumo()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
            .frame(minHeight: Self.actionAreaMinHeight)
        case .handResult:
            actionButton("次の局へ", color: Theme.coral) {
                model.advanceToNextHand()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
            .frame(minHeight: Self.actionAreaMinHeight)
        case .gameResult:
            actionButton("もう一度", color: Theme.coral) {
                model.startGame()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
            .frame(minHeight: Self.actionAreaMinHeight)
        }
    }

    private func actionButton(
        _ title: String, color: Color, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .disabled(disabled)
    }

    static let windNames = ["東", "南", "西", "北"]
}

// MARK: - Start Sheet

struct MahjongStartSheet: View {
    let onStart: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ゲームの流れ")
                        .themeBody(15).foregroundStyle(Theme.inkSub)
                    ruleRow("1", "CPU3人と東風戦（東1局〜東4局）。持ち点は25000点から")
                    ruleRow("2", "1枚ツモって1枚切る。4面子+雀頭で和了")
                    ruleRow("3", "聴牌したら立直できます（1000点を供託）。門前のときだけ")
                    ruleRow("4", "他の人の捨て牌はポン・チー・カンで鳴けます（鳴くと立直はできません）")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3))

                NavigationLink {
                    MahjongRuleSheet()
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("ルールと役を見る")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkSub)
                    }
                    .foregroundStyle(Theme.coral)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 3))
                }

                Spacer()
                Button {
                    onStart()
                } label: {
                    Text("対局開始").themeBody(18).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.coral)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("麻雀")
        }
        .presentationDetents([.large])
    }

    private func ruleRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.coral))
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
    }
}

// MARK: - Rule Sheet

struct MahjongRuleSheet: View {
    private let rules: [(String, String)] = [
        ("和了の形", "同じ牌3枚（刻子）か連番3枚（順子）を4組と、同じ牌2枚（雀頭）を1組そろえると和了です。ほかに七対子（対子7組）と国士無双もあります"),
        ("ツモとロン", "自分で引いた牌で和了すればツモ、他の人が切った牌で和了すればロンです"),
        ("役が要ります", "和了の形になっても、役が1つも無いと和了できません。立直・断幺九・役牌などが役です"),
        ("立直", "聴牌したら1000点を供託して宣言できます。以後は引いてきた牌をそのまま切ります（手牌は変えられません）。鳴いた手では宣言できません"),
        ("ポン・チー", "同じ牌が2枚あれば誰の捨て牌でもポン、連番であと2枚そろうときは上家（左の人）の捨て牌をチーできます。鳴くとその牌を含む面子を手牌の外に晒し、そのまま自分の番になって1枚切ります"),
        ("カン", "同じ牌4枚でカンできます。手の内の4枚なら暗槓、他の人の捨て牌でそろえば明槓、ポン済みの牌に4枚目を足せば加槓です。カンすると新しいドラがめくれ、王牌から1枚（嶺上牌）を引きます"),
        ("鳴くと何が変わるか", "立直・門前清自摸和・平和・一盃口・七対子は付かなくなり、三色同順・一気通貫・チャンタ・混一色などは1飜下がります。役牌のように鳴いても付く役をねらいます。暗槓だけは門前のままです"),
        ("フリテン", "自分の待ち牌を自分で捨てているとロンできません（ツモなら和了できます）"),
        ("流局", "山が尽きたら流局。聴牌していた人が3000点を分け合い、ノーテンの人が払います"),
        ("東風戦", "東1局から東4局までの4局。親が和了または聴牌で流局すると連荘して本場が増えます"),
        ("この版の範囲", "半荘は次の版で追加します。立直したあとのカン・食い替えの禁止・流し満貫はまだ入っていません"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(rules, id: \.0) { rule in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rule.0)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.coral)
                        Text(rule.1)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2))
                }
            }
            .padding(Theme.pad)
        }
        .popBackground()
        .navigationTitle("ルールと役")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
