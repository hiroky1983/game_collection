import SwiftUI
import Core
import MahjongTiles

// MARK: - 卓の描画（麻雀刷新 #736 / #737）
//
// 幾何は `MahjongTableLayout`（純関数）、面の図案は `MahjongTiles`。ここは「どの牌をどこに置くか」を
// モデルのスナップショット（`MahjongTableScene`）から組み立てるだけにする。
// 見た目の基準は `docs/ui-review/mahjong-3d/mock-v12.png`（会長承認 2026-09-13）。

/// 卓に描くものを `MahjongModel` から切り出した値。`MahjongTableView` はモデルを直接見ない
/// （描画の入力が値になっていれば、プレビュー・テスト・スクショの撮影シナリオが作りやすい）。
struct MahjongTableScene {
    /// 手番順（0=自分, 1=下家(右), 2=対面, 3=上家(左)）。`MahjongTableLayout` の seat と同じ。
    var discards: [[MahjongTile]]
    var melds: [[MahjongCall]]
    /// CPU の手牌の枚数（ツモ牌を含む）。自分（0）は使わない。
    var handCounts: [Int]
    var riichi: [Bool]
    var scores: [Int]
    var names: [String]
    /// 自風（0=東 1=南 2=西 3=北）。
    var seatWinds: [Int]
    /// 対局中の手番。決着後は nil。
    var currentPlayer: Int?
    var roundNumber: Int
    var honba: Int
    var riichiSticks: Int
    var remainingTiles: Int
    var doraIndicators: [MahjongTile]
    /// 飛行中で河にまだ置かない 1 枚（家, 何枚目）。`MahjongDiscardFlight` が着地したら nil。
    var hiddenDiscardSeat: Int?
    var hiddenDiscardIndex: Int?

    static let windNames = ["東", "南", "西", "北"]
}

/// 真上から見た縦長の雀卓（#927。以前は斜め上から見た台形）。木枠・フェルト・CPU の立て牌・4 家の河と副露・
/// 立直棒・中央パネル・ドラ。
/// 自分の手牌一覧（タップ対象）は `MahjongView` がこの上に重ねる。
struct MahjongTableView: View {
    let scene: MahjongTableScene
    let layout: MahjongTableLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            MahjongTableSurface(layout: layout)
            // CPU の手牌（奥の対面から先に、左右は奥から手前へ）
            MahjongTileBlockCanvas(blocks: standingBlocks)
                .frame(width: layout.size.width, height: layout.size.height)
            ForEach(0..<4, id: \.self) { seat in
                seatLayer(seat)
            }
            MahjongCenterPanel(scene: scene)
                .frame(width: layout.centerPanel.width, height: layout.centerPanel.height)
                .position(x: layout.centerPanel.midX, y: layout.centerPanel.midY)
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    private var standingBlocks: [(MahjongTileBlockGeometry, MahjongTileBlockFacing)] {
        var out: [(MahjongTileBlockGeometry, MahjongTileBlockFacing)] = []
        for seat in [2, 3, 1] {
            let count = max(0, scene.handCounts[seat])
            for i in 0..<count { out.append(layout.handBlock(seat: seat, index: i, count: count)) }
        }
        return out
    }

    /// 1 家ぶんの河・副露・立直棒。読み上げは家ごとに 1 要素にまとめる。
    private func seatLayer(_ seat: Int) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(scene.discards[seat].enumerated()), id: \.offset) { i, tile in
                if !(scene.hiddenDiscardSeat == seat && scene.hiddenDiscardIndex == i) {
                    let slot = layout.riverSlot(seat: seat, index: i)
                    let w = layout.riverTileWidth * slot.scale
                    MahjongTileView(tile: tile, width: w, height: w * MahjongTableLayout.tileAspect)
                        .rotationEffect(.degrees(slot.rotation))
                        .position(slot.center)
                }
            }
            if !scene.melds[seat].isEmpty {
                meldRow(seat)
            }
            if scene.riichi[seat] {
                let slot = layout.riichiStickSlot(seat: seat)
                riichiStick(scale: slot.scale)
                    .rotationEffect(.degrees(slot.rotation))
                    .position(slot.center)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seatAccessibilityLabel(seat))
    }

    /// 副露は各家の右手前の角に寄せる。`MahjongMeldRow` は横一列なので、角を基準に
    /// 「角から伸びる」向きへ揃えてから各家の角度に回す。
    @ViewBuilder
    private func meldRow(_ seat: Int) -> some View {
        if seat == 1 || seat == 3 {
            sideMelds(seat)
        } else {
            stackedMelds(seat)
        }
    }

    /// 上家・下家の副露。壁の列に沿って 1 枚ずつ置く（置き場は `MahjongTableLayout.sideMeldSlot`。
    /// 台形だった頃は列が斜めになるので 1 枚ずつ置いた。長方形でも組の間隔をそこで持てるので変えていない）。
    private func sideMelds(_ seat: Int) -> some View {
        let tiles: [(group: Int, tile: MahjongTile)] = scene.melds[seat].enumerated()
            .flatMap { gi, meld in meld.tiles.map { (group: gi, tile: $0) } }
        return ForEach(Array(tiles.enumerated()), id: \.offset) { ordinal, item in
            let slot = layout.sideMeldSlot(seat: seat, ordinal: ordinal, gaps: item.group)
            let w = layout.riverTileWidth * slot.scale
            MahjongTileView(tile: item.tile, width: w, height: w * MahjongTableLayout.tileAspect)
                .rotationEffect(.degrees(slot.rotation))
                .position(slot.center)
        }
    }

    /// 対面・自分の副露。1 組ずつ行を分けて積む（4 枚＝カンで 1 行）。
    private func stackedMelds(_ seat: Int) -> some View {
        let slot = layout.meldSlot(seat: seat)
        let w = layout.meldTileWidth(seat: seat) * slot.scale
        let frameWidth = layout.size.width * 0.42
        let row = MahjongMeldRow(melds: scene.melds[seat], tileWidth: w, showsBadge: false, maxTilesPerRow: 4)
        let rowHeight = w * 1.34 + 1
        // 4 行ぶん（4 組）の枠を取り、bottomTrailing に寄せて回す。対面は 180 度回転で bottomTrailing が
        // 左上へ来て行は下へ、自分は右下から上へ積まれる。`slot.center` が 1 組目の行の縦の中央
        // （`stackHeight` は打ち消し合う）。`MahjongTableLayout.meldRegion` はこの置き方を前提に矩形を出す。
        let stackHeight = rowHeight * 4
        let center = seat == 2
            ? CGPoint(x: slot.center.x + frameWidth / 2, y: slot.center.y + stackHeight / 2 - rowHeight / 2)
            : CGPoint(x: slot.center.x - frameWidth / 2, y: slot.center.y - stackHeight / 2 + rowHeight / 2)
        return row
            .frame(width: frameWidth, height: stackHeight, alignment: .bottomTrailing)
            .rotationEffect(.degrees(slot.rotation))
            .position(center)
    }

    private func riichiStick(scale: CGFloat) -> some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 46 * scale, height: 4 * scale)
            .overlay(Circle().fill(Color(hex: 0xFF3B2F)).frame(width: 3 * scale, height: 3 * scale))
            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
    }

    private func seatAccessibilityLabel(_ seat: Int) -> String {
        let name = seat == 0 ? "あなた" : scene.names[seat]
        return MahjongAccessibility.playerLabel(
            name: name, score: scene.scores[seat], isRiichi: scene.riichi[seat],
            isCurrent: scene.currentPlayer == seat, melds: scene.melds[seat]
        )
        + "。"
        + MahjongAccessibility.discardPileLabel(player: name, tiles: scene.discards[seat])
    }
}

// MARK: - 卓の面

/// 木枠とフェルト。長方形の卓（#927。以前は台形）を `Canvas` 1 枚に描く（照明の照りと縁の落ち影を含む）。
struct MahjongTableSurface: View {
    let layout: MahjongTableLayout

    var body: some View {
        Canvas { ctx, _ in
            let wood = Path { p in
                let f = layout.woodFrame
                p.move(to: f[0]); p.addLine(to: f[1]); p.addLine(to: f[2]); p.addLine(to: f[3]); p.closeSubpath()
            }
            ctx.fill(wood, with: .linearGradient(
                Gradient(colors: [Color(hex: 0xC48A4A), Color(hex: 0x8A5A2B), Color(hex: 0x4A2C12)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: layout.size.height)))
            let felt = Path { p in
                let f = layout.felt
                p.move(to: f[0]); p.addLine(to: f[1]); p.addLine(to: f[2]); p.addLine(to: f[3]); p.closeSubpath()
            }
            let center = layout.project(u: 0.5, v: 0.5).point
            ctx.fill(felt, with: .radialGradient(
                Gradient(colors: [Color(hex: 0x2E7A50), Color(hex: 0x2E7A50), Color(hex: 0x14432C)]),
                center: center, startRadius: layout.size.width * 0.1, endRadius: layout.size.height * 0.78))
            // 木枠の内側の落ち影（フェルトに切り抜いたぼかし線）
            var shadow = ctx
            shadow.clip(to: felt)
            shadow.addFilter(.blur(radius: layout.size.width * 0.01))
            shadow.stroke(felt, with: .color(Color.black.opacity(0.45)), lineWidth: layout.size.width * 0.016)
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .accessibilityHidden(true)
    }
}

// MARK: - 中央パネル（#737）

/// 黒い盤に、局・本場・供託・残り枚数と、4 家の風・点数・立直を各家の向きで LED 風に出す。
/// フォント資産は足さず、等幅数字と発光のグローで作る。
///
/// 盤は縦長の長方形（`MahjongTableLayout.centerPanel`。#927 で 70×70 → 90×108/393）。文字の大きさは
/// **幅**から取る（iPhone 17 の卓幅 361pt で盤の幅 82.7pt。局・風・点数が 11pt 以上になる比にしてある。
/// 会長 QA「真ん中のセクションが見えん」）。本場・供託だけは左右の家の行に挟まれた幅に収めるため 8pt 台。
struct MahjongCenterPanel: View {
    let scene: MahjongTableScene

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.08, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1A1A1E), Color(hex: 0x050506)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.08, style: .continuous)
                        .strokeBorder(Color(hex: 0x3A3A40), lineWidth: max(1, w * 0.02)))
                    .shadow(color: .black.opacity(0.6), radius: w * 0.07, y: w * 0.045)
                VStack(spacing: w * 0.02) {
                    led("東\(scene.roundNumber)局", size: w * 0.14, design: .rounded)
                    led("\(scene.remainingTiles)", size: w * 0.24)
                    led("本場\(scene.honba) 供託\(scene.riichiSticks)", size: w * 0.095, design: .rounded)
                        // 左右の家の行（盤の縁から w × 0.40 に置く）の内側に収める
                        .frame(maxWidth: w * 0.58)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(MahjongAccessibility.roundLabel(
                    roundNumber: scene.roundNumber, honba: scene.honba, remainingTiles: scene.remainingTiles))
                seat(2, angle: 180, offset: CGSize(width: 0, height: -h * 0.40), unit: w)
                seat(1, angle: -90, offset: CGSize(width: w * 0.40, height: 0), unit: w)
                seat(3, angle: 90, offset: CGSize(width: -w * 0.40, height: 0), unit: w)
                seat(0, angle: 0, offset: CGSize(width: 0, height: h * 0.40), unit: w)
            }
            .frame(width: w, height: h)
        }
        .accessibilityElement(children: .contain)
    }

    private func led(_ text: String, size: CGFloat, design: Font.Design = .monospaced) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: design))
            .monospacedDigit()
            // くすんで見えた（会長指摘）ので、芯を白に近い赤にして発光を強める
            .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFC9C2), Color(hex: 0xFF5A4C)], startPoint: .top, endPoint: .bottom))
            .shadow(color: Color(hex: 0xFF3B2F), radius: size * 0.12)
            .shadow(color: Color(hex: 0xFF3B2F).opacity(0.8), radius: size * 0.35)
            .shadow(color: Color(hex: 0xFF3B2F).opacity(0.5), radius: size * 0.7)
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    /// 1 家の行（風・点数・立直）。`unit` は盤の幅（文字の大きさの基準）。
    private func seat(_ index: Int, angle: Double, offset: CGSize, unit: CGFloat) -> some View {
        let isCurrent = scene.currentPlayer == index
        let wind = MahjongTableScene.windNames[scene.seatWinds[index]]
        let name = index == 0 ? "あなた" : scene.names[index]
        return HStack(spacing: unit * 0.04) {
            Text(wind)
                .font(.system(size: unit * 0.14, weight: .black, design: .rounded))
                .foregroundStyle(isCurrent ? Color(hex: 0xFFD54A) : Color(hex: 0xB8B8C0))
                .shadow(color: isCurrent ? Color(hex: 0xFFD54A).opacity(0.8) : .clear, radius: unit * 0.04)
            led("\(scene.scores[index])", size: unit * 0.135)
            if scene.riichi[index] {
                Text("立直")
                    .font(.system(size: unit * 0.09, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0xFF6A5C))
            }
        }
        .rotationEffect(.degrees(angle))
        .offset(offset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MahjongAccessibility.playerLabel(
            name: name, score: scene.scores[index], isRiichi: scene.riichi[index], isCurrent: isCurrent))
    }
}

// MARK: - 牌台（#738）

/// 手牌の帯の背景。以前は卓と同じフェルトだったが、卓が木枠付きの台形になったのに合わせ、
/// 手前の牌台も木のトレイにする（モック v12）。木目画像は使わず、茶系の多段グラデーション＋
/// 上端の照りと内側の落ち影で厚みを出す。
struct MahjongWoodTray: View {
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.corner, style: .continuous) }

    var body: some View {
        shape
            .fill(LinearGradient(colors: [Color(hex: 0xA6703A), Color(hex: 0x8A5A2B), Color(hex: 0x4A2C12)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                shape.inset(by: 2).strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.5)
            )
            .overlay(shape.strokeBorder(Color(hex: 0x3A2210).opacity(0.8), lineWidth: 2))
    }
}
