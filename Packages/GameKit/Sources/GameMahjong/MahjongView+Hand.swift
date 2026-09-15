import SwiftUI
import Core
import MahjongTiles

extension MahjongView {
    // MARK: - 手牌一覧（卓上）

    private static let handOverviewSpacing: CGFloat = MahjongTableLayout.handOverviewSpacing
    /// 一覧の牌は河と同じ大きさ（iPhone で幅 18pt・高さ 25pt ほど）で、そのままでは Apple 推奨の 44pt に届かない。
    /// **レイアウトは変えずに当たり判定だけ**この高さまで縦に広げる（`handOverviewTile`）。
    private static let handOverviewMinHitHeight: CGFloat = 44
    /// 一覧で選択中の牌を持ち上げる量。下部（`tableHandLift` 側の -10pt）と同じ言語だが、
    /// 牌が小さく行の高さも詰まっているので控えめにする。
    private static let handOverviewLift: CGFloat = 3

    /// 卓の上（フェルトの手前の縁）に置く、手牌14枚を河の牌と同じ大きさで一目で見渡せる一覧。
    ///
    /// **この一覧からも打牌できる**（#378・会長発案）。以前はタップを卓下部の `handOnTable`
    /// （大きい牌・横スクロール）に一本化し、こちらは視認専用にしていたが、一覧で切りたい牌を
    /// 見つけても下部までスクロールして探し直さないと切れず二度手間だった。牌の ID を下部と
    /// 共有する（`MahjongHandTap.handTileID(index:)`）ので、**どちらの面でタップしても選択は同じ**で、
    /// 2タップ目の確定もどちらの面からでも成立する。
    ///
    /// 読み上げは従来どおり下部に一本化する（この一覧は `accessibilityHidden`。VoiceOver 利用時は
    /// 同じ操作が下部の `handTile` にラベル・ヒント付きで揃っている）。
    func handOverviewOnTable(width: CGFloat, tileWidth: CGFloat) -> some View {
        let hand = model.playerHand.tiles
        let drawn = model.playerDrawnTile
        // 切れる牌の判定は手牌の枚数ぶん走るので、1 回だけ求めて配る（`handOnTable` と同じ考え方）。
        let discardable = model.discardableTiles
        let tileCount = hand.count + (drawn != nil ? 1 : 0)
        let totalSpacing = Self.handOverviewSpacing * CGFloat(max(0, tileCount - 1))
        // 牌の幅は河の牌と同じ（`MahjongTableLayout.handOverview`。会長指摘 2026-09-13）。
        // 幅は 14 枚が収まるように決まっているので普段は縮まないが、念のため収まる幅に丸める。
        let rawWidth = tileCount > 0 ? (width - totalSpacing) / CGFloat(tileCount) : tileWidth
        let tileWidth = max(10, min(tileWidth, rawWidth))
        let tileHeight = tileWidth * MahjongTableLayout.tileAspect
        return HStack(spacing: Self.handOverviewSpacing) {
            ForEach(Array(hand.enumerated()), id: \.offset) { index, tile in
                handOverviewTile(
                    tile, id: MahjongHandTap.handTileID(index: index),
                    width: tileWidth, height: tileHeight, isDrawn: false, discardable: discardable
                )
            }
            if let drawn {
                handOverviewTile(
                    drawn, id: MahjongHandTap.drawnTileID,
                    width: tileWidth, height: tileHeight, isDrawn: true, discardable: discardable
                )
            }
        }
        // 左詰め（#960）: 1 枚目の位置がツモの有無で動かず、鳴いて減った右側に副露（`MahjongTableView.inlineMelds`）
        // が入る。牌の中心は `MahjongTableLayout.handOverviewTileCenter` と同じ計算。
        .frame(width: width, alignment: .leading)
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }

    /// 一覧の 1 枚。打牌の判定は下部の `handTile` と同じ `MahjongHandTap` を通す。
    private func handOverviewTile(
        _ tile: MahjongTile, id: String, width: CGFloat, height: CGFloat,
        isDrawn: Bool, discardable: Set<MahjongTile>
    ) -> some View {
        let canDiscard = discardable.contains(tile)
        let isSelected = selectedTileID == id
        // 当たり判定だけを縦へ伸ばす: 余白を足してから `contentShape` を取り、同じ量を負の余白で
        // 引き戻す。牌そのものの大きさも行の高さも変わらないまま、指の当たる範囲だけが広がる。
        let hitPadding = max(0, (Self.handOverviewMinHitHeight - height) / 2)
        return MahjongTileView(
            tile: tile, width: width, height: height,
            // 立直中に切れない牌は下部と同じく暗く落とす。ここで見分けが付かないと
            // 「一覧をタップしても反応しない牌がある」という理由の分からない挙動になる。
            isBlocked: model.isPlayerTurn && !canDiscard,
            isSelected: isSelected,
            isHinted: isDrawn
        )
        .offset(y: isSelected ? -Self.handOverviewLift : 0)
        .padding(.vertical, hitPadding)
        .contentShape(Rectangle())
        .padding(.vertical, -hitPadding)
        .onTapGesture {
            handleHandTap(tile, id: id, canDiscard: canDiscard, scrollsBottomHand: true)
        }
        .disabled(!model.isPlayerTurn)
    }

    // MARK: - 手牌

    /// 会長指摘「持ち牌もグリーンの卓の上に一列に並べて見てほしい」「横スクロールは維持して」への対応。
    /// 以前の 7列×2段の白カードをやめ、卓と同じ緑フェルトの帯に単列（横スクロール）で並べる。
    /// 名前・風・点数は卓の中央パネル（`MahjongCenterPanel`・#737）に一本化したので、ここでは持たない。
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
    ///
    /// 牌・間隔・ツモ牌の隙間は `MahjongHandRowMetrics`（iPhone は 34×46pt 固定、iPad は捨て牌より小さくならないよう相似に広げる・#715）。
    private var handRowMetrics: MahjongHandRowMetrics { .make(layout: adaptiveLayout) }
    /// 選択時に牌を -10pt 持ち上げる演出が ScrollView の上端で切れないための余白。
    private static let tableHandLift: CGFloat = 12

    var handOnTable: some View {
        // 切れる牌の判定は手牌の枚数ぶん走るので、1 回だけ求めて配る（#190 と同じ考え方）。
        let discardable = model.discardableTiles
        let waits = model.playerWaits
        // model.playerHand.tiles を直接使う（常にソート済み）。以前は差分適用のローカル state を
        // 挟んでいたが、末尾に追加するだけだとソート順が崩れて「並び替えが効かない」不具合になった。
        let hand = model.playerHand.tiles
        let drawn = model.playerDrawnTile
        let metrics = handRowMetrics
        return VStack(spacing: 6) {
            // 卓上の一覧（`handOverviewOnTable`）から選んだ牌はこの行の表示範囲外にあることが
            // 多いので、そこまで送れるように `ScrollViewReader` で包む（#378）。
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: metrics.spacing) {
                        // identity は **配列の位置**（`\.offset`）にする。牌の値を identity にすると、
                        // 途中の1枚が抜けて別の牌が別の位置に挿さったとき「生き残った牌が別スロットへ
                        // 移動した」と SwiftUI に解釈され、横滑りを補間できる状態になってしまう
                        // （Opus 指摘）。手牌は毎回ゼロから並べ直す配列なので、位置 identity にすれば
                        // 各スロットは「同じ View の中身が差し替わるだけ」になり、動きようがない。
                        // `.id` に渡す値も同じ位置由来なので、スクロールの宛先を足しても
                        // identity は動かない（値が変われば identity が切れる点に注意）。
                        ForEach(Array(hand.enumerated()), id: \.offset) { index, tile in
                            let id = MahjongHandTap.handTileID(index: index)
                            handTile(tile, id: id, isDrawn: false, discardable: discardable)
                                .id(id)
                        }
                        Spacer().frame(width: metrics.drawnGap)
                        // ツモ牌が無い間も同じ幅の透明プレースホルダーを置き、コンテンツの総幅を
                        // 常に一定に保つ。ツモ牌の出入りで ScrollView の contentSize が変わると
                        // UIScrollView 側がスクロール位置を自前で補正することがあるため、幅そのものを
                        // 固定してその発火条件自体を無くす。
                        ZStack {
                            Color.clear
                            if let drawn {
                                handTile(
                                    drawn, id: MahjongHandTap.drawnTileID,
                                    isDrawn: true, discardable: discardable
                                )
                            }
                        }
                        .frame(width: metrics.tileWidth, height: metrics.tileHeight)
                        // ツモ牌が無い間もこの枠は残るので、スクロールの宛先は常に解決できる。
                        .id(MahjongHandTap.drawnTileID)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, Self.tableHandLift)
                    .padding(.bottom, 6)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .defaultScrollAnchor(.leading)
                .frame(height: metrics.tileHeight + Self.tableHandLift + 6)
                // 並び替え・出し入れは瞬時に反映するだけにする（雀卓側と同じ考え方）。
                // 選択（浮き上がり）演出は handTile 側で個別に `.animation` を付け直しているので、
                // ここで止めても影響しない。
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
                .onChange(of: overviewScrollTarget) {
                    guard let target = overviewScrollTarget else { return }
                    // アニメーションは付けない。この行は「ルーレット現象」（上のコメント参照）の
                    // 反省で徹底して動きを止めてある場所で、ここだけ横滑りを足すと同じ見え方に
                    // 逆戻りする。瞬時に位置が変わるだけなら Reduce Motion とも整合する。
                    proxy.scrollTo(target, anchor: .center)
                    overviewScrollTarget = nil
                }
            }
            // 副露は「卓の上においてほしい」（会長指摘）ため卓上の手牌一覧の右隣（`MahjongTableView.inlineMelds`。#960）
            // に置く。ここ（操作用のスクロール行）には置かない。
            hintLine(waits: waits)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        // 木の牌台（#738）。卓が木枠付きになったのに合わせる。
        // 影は台自身に付ける（外側に付けると手牌の1枚1枚にまで影が落ちる）。
        .background(MahjongWoodTray().shadow(color: .black.opacity(0.22), radius: 6, y: 3))
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
            width: handRowMetrics.tileWidth,
            height: handRowMetrics.tileHeight,
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
            // 下部をタップしたときは指の下でこの行が動くと邪魔なのでスクロールは追従させない。
            handleHandTap(tile, id: id, canDiscard: canDiscard, scrollsBottomHand: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            MahjongAccessibility.handTileLabel(tile, isDrawn: isDrawn, isDiscardable: canDiscard)
        )
        .accessibilityHint("ダブルタップでこの牌を切ります")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            // VoiceOver の打牌もタップと同じ位置から飛ばす（verifier 指摘）
            pendingDiscardSlot = (index: MahjongHandTap.handIndex(of: id) ?? model.playerHand.tiles.count,
                                  count: model.playerHand.tiles.count + (model.playerDrawnTile != nil ? 1 : 0))
            model.discard(tile)
        }
        .disabled(!model.isPlayerTurn)
    }

    /// 卓上の一覧と卓下の操作行に共通の打牌タップ処理（#378）。判定そのものは `MahjongHandTap`
    /// に置いてあり、どちらの面から来ても同じ2段階（1タップ目=選択・2タップ目=打牌）を通る。
    ///
    /// `scrollsBottomHand` は「選んだ牌が下部の表示範囲外かもしれない」一覧側でだけ true にする。
    private func handleHandTap(
        _ tile: MahjongTile, id: String, canDiscard: Bool, scrollsBottomHand: Bool
    ) {
        switch MahjongHandTap.outcome(
            tappedID: id, selectedID: selectedTileID,
            isPlayerTurn: model.isPlayerTurn, isDiscardable: canDiscard
        ) {
        case .ignored:
            return
        case .select(let selected):
            selectedTileID = selected
            if scrollsBottomHand { overviewScrollTarget = selected }
        case .discard:
            // 選択解除と打牌を同じトランザクションにする。別々のフレームに分かれると
            // 「選択解除」→「手牌の入れ替え」の2段ジャンプに見えることがある（Opus指摘）。
            // 切る前に、この牌が一覧の何枚目にあったかを控える（打牌の飛び出し位置。ツモ牌は末尾）。
            let handCount = model.playerHand.tiles.count
            let overviewCount = handCount + (model.playerDrawnTile != nil ? 1 : 0)
            pendingDiscardSlot = (
                index: MahjongHandTap.handIndex(of: id) ?? handCount,
                count: overviewCount
            )
            var transaction = Transaction()
            transaction.animation = nil
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTileID = nil
                model.discard(tile)
            }
        }
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
}
