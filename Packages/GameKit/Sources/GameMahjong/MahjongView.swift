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
            HowToPlayHint(.mahjong, playLog: services.playLog)
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
    private static let discardMaxTiles = 18
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
    /// 配置は Stack 任せの自動フロー（以前の実装）だと「3人の名前が全員上に並んで見える」
    /// 結果になり実機で確認して分かった（会長のスクリーンショット指摘）。Stack の自動配置に
    /// 委ねず、`ZStack` + `position()` で卓の四辺（上/左/右/下）に明示的な座標を与える。
    /// `position()` は指定した点を**その View の中心**に置くだけで、View 自身のサイズは
    /// 考慮してくれない。牌基準の余白だけで座標を決めたところ、名前チップ（牌より幅がある）や
    /// 複数段になった河がその分だけ卓の外へはみ出し、右側は画面端で切れた
    /// （会長のスクリーンショットで発覚）。各要素に明示的な幅・高さの枠を持たせ、
    /// その枠を基準に座標を計算する（枠の中では `alignment: .top` で内容を上詰めにする）。
    // 会長指摘: 上下(横長1行)と左右(縦積み2行)でチップの形が違うのがキモい。1種類のチップに
    // 統一し、左右の列は折り返さないぶんだけ幅を広げる（卓＝緑の正方形自体の大きさには効かないので
    // 「卓に影響ないなら大きくしてOK」の条件を満たす）。
    private static let sideColumnWidth: CGFloat = 128
    private static let sideColumnHeight: CGFloat = 150
    private static let edgeRowHeight: CGFloat = 96

    private var mahjongTable: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let tileWidth = Self.discardTileWidth(forTableSide: side)
            let edgeRowWidth = side - Self.tablePadding * 2
            let topY = Self.tablePadding + Self.edgeRowHeight / 2
            let bottomY = side - Self.tablePadding - Self.edgeRowHeight / 2
            let sideX = Self.tablePadding + Self.sideColumnWidth / 2
            ZStack {
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

                // 会長指摘「卓上にもUIが欲しい」への対応: 卓の中央がただの空き地だったので、
                // 実物の卓中央（点棒・ドラ表示・残り枚数が集まる場所）にならって小さな盤面を置く。
                tableCenterPanel
                    .position(x: side / 2, y: side / 2)

                // 会長指摘: 縦(左右)の河は卓に対して中央寄せ、横(上下)の河も中心に寄せたい。
                // 予約した枠の中で `alignment: .top`（上詰め）にしていたのを `.center` に変える。
                opponentRow(2, tileWidth: tileWidth) // 対面
                    .frame(width: edgeRowWidth, height: Self.edgeRowHeight, alignment: .center)
                    .position(x: side / 2, y: topY)
                opponentColumn(3, tileWidth: tileWidth) // 上家（左）
                    .frame(width: Self.sideColumnWidth, height: Self.sideColumnHeight, alignment: .center)
                    .position(x: sideX, y: side / 2)
                opponentColumn(1, tileWidth: tileWidth) // 下家（右）
                    .frame(width: Self.sideColumnWidth, height: Self.sideColumnHeight, alignment: .center)
                    .position(x: side - sideX, y: side / 2)
                playerDiscardOnTable(tileWidth: tileWidth) // 自分
                    .frame(width: edgeRowWidth, height: Self.edgeRowHeight, alignment: .center)
                    .position(x: side / 2, y: bottomY)
            }
            .frame(width: side, height: side)
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
    private var tableCenterPanel: some View {
        VStack(spacing: 5) {
            Text("東\(model.roundNumber)局\(model.honba > 0 ? " \(model.honba)本場" : "")")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let dora = model.doraIndicators.first {
                HStack(spacing: 4) {
                    Text("ドラ")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    MahjongTileView(tile: dora, width: 18, height: 24)
                }
            }
            Text("残り\(model.remainingTiles)枚")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.18)))
        .accessibilityHidden(true)
    }

    /// 会長指摘「上下は横長・左右は2列でUIがキモい」への対応: 4 席すべて同じ横一列のチップに
    /// 統一する。リーチは別の小さなカプセルを浮かせるのではなく、**同じチップの中**で
    /// 背景色を変え、末尾に「立直」タグを添える形にして「セクションの中でわかる」ようにする。
    private func opponentNameChip(_ index: Int, icon: String = "cpu") -> some View {
        let isCurrent = model.currentPlayer == index && model.phase == .playing
        let isRiichi = model.riichi[index]
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isCurrent ? Theme.coral : Theme.Fixed.ink.opacity(0.6))
            Text("\(model.playerName(index))・\(Self.windNames[model.seatWind(index)])")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Fixed.ink)
                .lineLimit(1).minimumScaleFactor(0.75)
            Text("\(model.scores[index])")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(model.scores[index] < 0 ? Theme.coral : Theme.Fixed.ink.opacity(0.7))
                .lineLimit(1)
            if isRiichi {
                Text("立直")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.coral))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(isRiichi ? Theme.coral.opacity(0.18) : Color.white.opacity(0.85)))
        .overlay(Capsule().strokeBorder(isRiichi ? Theme.coral.opacity(0.55) : .clear, lineWidth: 1.5))
        // 上家・下家の列は `sideColumnWidth` が狭いぶん、周りの VStack に幅を合わせて
        // 潰される（「25,0...」と省略されてしまっていた）。`.frame()` は既定でクリップしないので、
        // 自然な幅のまま列の外へ少しはみ出させて省略を防ぐ。
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 対面（横一列の河）。
    private func opponentRow(_ index: Int, tileWidth: CGFloat) -> some View {
        VStack(spacing: 3) {
            opponentNameChip(index)
            discardStrip(model.discards[index], tileWidth: tileWidth, perRow: Self.discardPerRow, maxTiles: Self.discardMaxTiles)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(opponentAccessibilityLabel(index))
    }

    /// 上家・下家（縦に細い帯の河。回転はさせない）。チップは対面・自分と同じ `opponentNameChip`。
    private func opponentColumn(_ index: Int, tileWidth: CGFloat) -> some View {
        VStack(spacing: 3) {
            opponentNameChip(index)
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
            isRiichi: model.riichi[index], isCurrent: isCurrent
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
    private func playerDiscardOnTable(tileWidth: CGFloat) -> some View {
        VStack(spacing: 4) {
            opponentNameChip(MahjongModel.humanIndex, icon: "person.fill")
            discardStrip(
                model.discards[MahjongModel.humanIndex],
                tileWidth: tileWidth, perRow: Self.discardPerRow, maxTiles: Self.discardMaxTiles
            )
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

    // MARK: - 手牌

    /// 会長指摘「持ち牌もグリーンの卓の上に一列に並べて見てほしい」への対応。
    /// 以前の 7列×2段の白カードをやめ、卓と同じ緑フェルトの帯に単列で並べる。
    /// 名前・風・点数は自分の河側（`playerDiscardOnTable`）のチップに一本化したので、ここでは持たない。
    ///
    /// **「ルーレット」の正体**: 当初 `ScrollView(.horizontal)` に乗せていたが、これが真犯人だった。
    /// ドラ牌の出し入れで中身の幅が変わるたびに、SwiftUI のアニメーション無効化
    /// （`.transaction { $0.animation = nil }`）が一切効かない **UIScrollView 側のネイティブな
    /// スクロール位置補正**が走り、表示中の牌が横へ流れて見えていた（録画をコマ送りして確認済み）。
    /// 牌が入れ替わったのではなく、スクロール位置がひとりでにズレていただけ。
    /// スクロールという概念自体をやめ、常に横幅いっぱいに収まるよう牌の幅を動的に縮める方式にする。
    private static let tableHandTileWidth: CGFloat = 34
    private static let tableHandTileHeight: CGFloat = 46
    private static let tableHandSpacing: CGFloat = 3
    private static let tableHandDrawnGap: CGFloat = 8

    private var handOnTable: some View {
        // 切れる牌の判定は手牌の枚数ぶん走るので、1 回だけ求めて配る（#190 と同じ考え方）。
        let discardable = model.discardableTiles
        let waits = model.playerWaits
        // model.playerHand.tiles を直接使う（常にソート済み）。以前は差分適用のローカル state を
        // 挟んでいたが、末尾に追加するだけだとソート順が崩れて「並び替えが効かない」不具合になった。
        let hand = model.playerHand.tiles
        let drawn = model.drawnTile
        let tileCount = hand.count + (drawn != nil ? 1 : 0)
        return VStack(spacing: 6) {
            GeometryReader { geo in
                let gap = drawn != nil ? Self.tableHandDrawnGap : 0
                let totalSpacing = Self.tableHandSpacing * CGFloat(max(0, tileCount - 1)) + gap
                let rawWidth = tileCount > 0
                    ? (geo.size.width - totalSpacing) / CGFloat(tileCount) : Self.tableHandTileWidth
                let tileWidth = max(18, min(Self.tableHandTileWidth, rawWidth))
                HStack(spacing: Self.tableHandSpacing) {
                    ForEach(Self.stableHandIDs(hand), id: \.id) { entry in
                        handTile(entry.tile, id: entry.id, isDrawn: false, discardable: discardable, width: tileWidth)
                    }
                    if let drawn {
                        Spacer().frame(width: gap)
                        handTile(drawn, id: "drawn", isDrawn: true, discardable: discardable, width: tileWidth)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .frame(height: Self.tableHandTileHeight)
            // 並び替え・出し入れは瞬時に反映するだけにする（雀卓側と同じ考え方）。
            // 選択（浮き上がり）演出は handTile 側で個別に `.animation` を付け直しているので、
            // ここで止めても影響しない。
            .transaction { $0.animation = nil }
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

    /// 手牌に同じ牌が複数あっても安定した id を割り当てる（牌の値＋同値内の出現順）。
    private static func stableHandIDs(
        _ tiles: [MahjongTile]
    ) -> [(tile: MahjongTile, id: String)] {
        var seen: [MahjongTile: Int] = [:]
        return tiles.map { tile in
            let n = seen[tile, default: 0]
            seen[tile] = n + 1
            return (tile, "\(tile)#\(n)")
        }
    }

    /// 会長指摘「誤タップ防止のため1タップでフォーカス、2タップ目で捨てる」への対応。
    /// 1回目のタップは選択（アウトライン＋浮き上がり）だけ。同じ牌をもう一度タップしたときだけ
    /// 実際に `model.discard` を呼ぶ。別の牌をタップした場合は選択を切り替えるだけで切らない。
    private func handTile(
        _ tile: MahjongTile, id: String, isDrawn: Bool, discardable: Set<MahjongTile>, width: CGFloat
    ) -> some View {
        let canDiscard = discardable.contains(tile)
        let isSelected = selectedTileID == id
        return MahjongTileView(
            tile: tile,
            width: width,
            height: Self.tableHandTileHeight,
            isBlocked: model.isPlayerTurn && !canDiscard,
            isHinted: isDrawn
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Theme.coral, lineWidth: isSelected ? 2.5 : 0)
        )
        .shadow(color: isSelected ? .black.opacity(0.3) : .clear, radius: isSelected ? 5 : 0, y: 3)
        .offset(y: isSelected ? -10 : 0)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            guard model.isPlayerTurn, canDiscard else { return }
            if isSelected {
                model.discard(tile)
                selectedTileID = nil
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

    private var handResultTitle: String {
        guard let result = model.handResult else { return "" }
        switch result.kind {
        case .exhaustiveDraw: return "流局"
        case .tsumo:  return "\(model.playerName(result.winner ?? 0))のツモ"
        case .ron:    return "\(model.playerName(result.winner ?? 0))のロン"
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

    private var scoreTable: some View {
        VStack(spacing: 2) {
            ForEach(0..<MahjongModel.playerCount, id: \.self) { player in
                HStack {
                    Text(model.playerName(player))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                    Spacer()
                    Text("\(model.scores[player])点")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(model.scores[player] < 0 ? Theme.coral : Theme.ink)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 操作

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
        case .playing:
            HStack(spacing: 12) {
                if model.isDeclaringRiichi {
                    actionButton("やめる", color: Theme.fillMuted) { model.cancelRiichiDeclaration() }
                } else {
                    actionButton("立直", color: Theme.purple, disabled: !model.canDeclareRiichi) {
                        model.declareRiichi()
                    }
                }
                actionButton("ツモ", color: Theme.coral, disabled: !model.canDeclareTsumo) {
                    model.declareTsumo()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .handResult:
            actionButton("次の局へ", color: Theme.coral) {
                model.advanceToNextHand()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .gameResult:
            actionButton("もう一度", color: Theme.coral) {
                model.startGame()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
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
                    ruleRow("3", "聴牌したら立直できます（1000点を供託）")
                    ruleRow("4", "鳴き（ポン・チー・カン）はこの版では使いません")
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
        ("立直", "聴牌したら1000点を供託して宣言できます。以後は引いてきた牌をそのまま切ります（手牌は変えられません）"),
        ("フリテン", "自分の待ち牌を自分で捨てているとロンできません（ツモなら和了できます）"),
        ("流局", "山が尽きたら流局。聴牌していた人が3000点を分け合い、ノーテンの人が払います"),
        ("東風戦", "東1局から東4局までの4局。親が和了または聴牌で流局すると連荘して本場が増えます"),
        ("この版の範囲", "鳴き（ポン・チー・カン）と半荘は次の版で追加します。役満は門前で出来るものだけ数えます"),
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
