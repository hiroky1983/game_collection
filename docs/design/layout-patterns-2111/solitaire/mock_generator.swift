// #2429 のレイアウト検討モック（ソリティア・今 vs A）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/GameSolitaireTests/` にコピーし、
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2429
// で `<出力先>/mock2429/` に PNG 2 枚と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 実物の部品（SolitaireCardBody・CardSlot・CardDragLayer・GameStatusBar・GameOverflowBar・CardTableSurface・
// GameControlArea）をそのまま使い、ナビバー・ステータスバー・バナーだけ見た目を写して描いている。
// 盤は `SolitaireBoardView` の写し（ScrollView は ImageRenderer で白紙になるので、同じ並べ方を ScrollView 無しで組む）。
// 終わったらコピーは消す（コミットしない）。#2427（麻雀ソリティア）の生成器と同じ型。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreTestSupport
@testable import GameSolitaire

private typealias Metrics = SolitaireMetrics

private struct Phone {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let scale: CGFloat
    /// iOS 26 のナビバーの高さ（実スクショ ip17_spiderzoom_v2cur.png の実測: コンテンツ開始 = 62 + 54 = 116pt）。
    static let navBarHeight: CGFloat = 54
}

private let phones = [
    Phone(name: "ip17", width: 402, height: 874, safeTop: 62, safeBottom: 34, scale: 3),
    Phone(name: "se3", width: 375, height: 667, safeTop: 20, safeBottom: 0, scale: 2),
]

/// 描画中に GeometryReader から寸法を書き留める器。
private final class Measure: @unchecked Sendable {
    var values: [String: Double] = [:]
    func set(_ key: String, _ value: CGFloat) { values[key] = (Double(value) * 100).rounded() / 100 }
}

/// ドラッグ中の札（指を離す前）。元の列の札は薄くし、指の位置に持ち上げた並びを描く。
private struct Lift {
    let pile: Int
    let from: Int
    let cards: [SolitaireCard]
    /// 指の位置（盤の座標。列 `overPile` の上に重ねる）。
    let overPile: Int
}

// MARK: - 盤（SolitaireBoardView の写し・ScrollView 無し）

private struct BoardCanvas: View {
    let model: SolitaireModel
    let metrics: PlayingCardMetrics
    let lift: Lift?

    var body: some View {
        VStack(spacing: 12) {
            topRow
            tableau
        }
        .frame(width: Metrics.boardWidth(cardWidth: metrics.width))
        .padding(.top, 2)
    }

    private var topRow: some View {
        HStack(spacing: Metrics.columnGap) {
            stock
            waste
            Spacer(minLength: 0)
            ForEach(SolitaireSuit.allCases, id: \.rawValue) { suit in
                foundation(suit)
            }
        }
    }

    @ViewBuilder private var stock: some View {
        if model.board.stock.isEmpty {
            CardSlot(metrics: metrics, systemImage: "arrow.clockwise")
        } else {
            ZStack {
                PlayingCardSurface(faceUp: false, cornerRadius: metrics.cornerRadius)
                PlayingCardBack(metrics: metrics)
            }
            .frame(width: metrics.width, height: metrics.height)
        }
    }

    private var waste: some View {
        let visible = Array(model.board.waste.suffix(model.rules.drawCount))
        let step = Metrics.wasteFanStep(cardWidth: metrics.width)
        return Group {
            if visible.isEmpty {
                CardSlot(metrics: metrics)
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, card in
                        let isTop = index == visible.count - 1
                        SolitaireCardBody(card: card, faceUp: true,
                                          isSelected: isTop && model.selection == .waste,
                                          isCovered: !isTop, metrics: metrics)
                            .offset(x: CGFloat(index) * step)
                    }
                }
            }
        }
        .frame(width: Metrics.wasteWidth(cardWidth: metrics.width, visibleCount: model.rules.drawCount),
               height: metrics.height, alignment: .topLeading)
    }

    @ViewBuilder private func foundation(_ suit: SolitaireSuit) -> some View {
        let rank = model.board.foundations[suit.rawValue]
        if rank > 0 {
            SolitaireCardBody(card: SolitaireCard(suit, rank), faceUp: true,
                              isSelected: false, isCovered: false, metrics: metrics)
        } else {
            CardSlot(metrics: metrics, suitSymbol: suit.symbol)
        }
    }

    private var tableau: some View {
        HStack(alignment: .top, spacing: Metrics.columnGap) {
            ForEach(0..<SolitaireBoard.pileCount, id: \.self) { pile in
                pileView(pile)
            }
        }
    }

    private func pileView(_ pile: Int) -> some View {
        let column = model.board.tableau[pile]
        let downStep = Metrics.faceDownStep(cardHeight: metrics.height)
        let upStep = Metrics.faceUpStep(cardHeight: metrics.height)
        let height = Metrics.pileHeight(faceDownCount: column.faceDown.count,
                                        faceUpCount: column.faceUp.count, cardHeight: metrics.height)
        return ZStack(alignment: .top) {
            if column.isEmpty {
                CardSlot(metrics: metrics, systemImage: "crown")
            } else {
                Color.clear.frame(width: metrics.width, height: height)
            }
            ForEach(Array(column.faceDown.enumerated()), id: \.element.id) { index, card in
                SolitaireCardBody(card: card, faceUp: false, isSelected: false, isCovered: false, metrics: metrics)
                    .padding(.top, CGFloat(index) * downStep)
            }
            ForEach(Array(column.faceUp.enumerated()), id: \.element.id) { index, card in
                let restY = CGFloat(column.faceDown.count) * downStep + CGFloat(index) * upStep
                let lifted = lift.map { $0.pile == pile && index >= $0.from } ?? false
                SolitaireCardBody(card: card, faceUp: true,
                                  isSelected: model.selection == .tableau(pile: pile, cardIndex: index),
                                  isCovered: index < column.faceUp.count - 1, metrics: metrics)
                    .opacity(lifted ? 0.35 : 1)
                    .padding(.top, restY)
            }
        }
        .frame(width: metrics.width, height: height, alignment: .top)
    }
}

/// 盤（卓の内側）。ScrollView の先頭（スクロール位置 0）で見えている範囲を描き、
/// 札の寸法・中身の高さ・スクロール無しで見える割合を書き留める。
private struct Board: View {
    let model: SolitaireModel
    let lift: Lift?
    let measure: Measure
    let prefix: String

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let width = Metrics.cardWidth(availableWidth: size.width)
            let metrics = Metrics.faceMetrics(width: width)
            let upStep = Metrics.faceUpStep(cardHeight: metrics.height)
            let downStep = Metrics.faceDownStep(cardHeight: metrics.height)
            let tallest = model.board.tableau.map {
                Metrics.pileHeight(faceDownCount: $0.faceDown.count, faceUpCount: $0.faceUp.count, cardHeight: metrics.height)
            }.max() ?? metrics.height
            // 中身の高さ: 上の余白 2 + 上段 + 間 12 + いちばん長い列。
            let contentH = 2 + metrics.height + 12 + tallest
            // 7 列目（伏せ 6 枚）にスクロール無しで積める表向きの枚数（K から A まで 13 枚が上限）。
            let room = size.height - (2 + metrics.height + 12) - 6 * downStep - metrics.height
            let capacity = max(0, min(13, Int(floor(room / upStep)) + 1))
            let frame = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).board_w_pt", size.width)
                measure.set("\(prefix).board_h_pt", size.height)
                measure.set("\(prefix).board_top_pt", frame.minY)
                measure.set("\(prefix).card_w_pt", metrics.width)
                measure.set("\(prefix).card_h_pt", metrics.height)
                measure.set("\(prefix).step_pt", upStep)
                measure.set("\(prefix).step_down_pt", downStep)
                measure.set("\(prefix).content_h_pt", contentH)
                measure.set("\(prefix).visible_ratio", min(1, size.height / contentH))
                measure.set("\(prefix).pile7_faceup_capacity", CGFloat(capacity))
            }()
            BoardCanvas(model: model, metrics: metrics, lift: lift)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
                .overlay(alignment: .topLeading) {
                    if let lift {
                        // 指の位置: 重ねる列の中央、上段の下から札 1.6 枚ぶん下。
                        let boardLeft = (size.width - Metrics.boardWidth(cardWidth: width)) / 2
                        let x = boardLeft + CGFloat(lift.overPile) * (width + Metrics.columnGap) + width / 2
                        let y = 2 + metrics.height + 12 + metrics.height * 1.6
                        CardDragLayer(cards: lift.cards,
                                      grab: CGSize(width: metrics.width / 2, height: metrics.height / 3),
                                      location: CardDragLocation(point: CGPoint(x: x, y: y)),
                                      step: upStep) { index, card in
                            SolitaireCardBody(card: card, faceUp: true, isSelected: false,
                                              isCovered: index < lift.cards.count - 1, metrics: metrics)
                        }
                    }
                }
        }
    }
}

// MARK: - 共通部品（ヘッダー・操作の段・バナー）

private struct StatusStrip: View {
    let phone: Phone
    let onFelt: Bool
    var body: some View {
        HStack {
            Text("9:41").font(.system(size: 17, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(onFelt ? Color.white : Theme.ink)
        .padding(.horizontal, phone.safeTop > 30 ? 40 : 16)
        .frame(height: phone.safeTop, alignment: phone.safeTop > 30 ? .center : .bottom)
    }
}

private struct GlassCircle<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.surface).shadow(color: Theme.cardShadow, radius: 8, y: 3))
    }
}

/// iOS 26 の「戻る ＋ ゲーム名 ＋ 右のアイコン群（？・新規ゲーム）」。
private struct NavHeader: View {
    let title: String
    let onFelt: Bool
    var body: some View {
        HStack(spacing: 8) {
            GlassCircle { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.coral) }
            Spacer(minLength: 0)
            Text(title)
                .themeBody(20, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(onFelt ? Color.white : Theme.ink)
                .shadow(color: onFelt ? .black.opacity(0.35) : .clear, radius: 2, y: 1)
            Spacer(minLength: 0)
            HStack(spacing: 24) {
                Image(systemName: "questionmark.circle")
                Image(systemName: "plus.circle.fill")
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.coral)
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(Capsule().fill(Theme.surface).shadow(color: Theme.cardShadow, radius: 8, y: 3))
        }
        .padding(.horizontal, 16)
        .frame(height: Phone.navBarHeight)
    }
}

private struct EllipsisButton: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.fillMuted))
    }
}

/// 段の中身（`SolitaireControlsView.actions` の写し: 戻す・ヒント）。
@MainActor
private func controlActions(model: SolitaireModel) -> [GameActionItem] {
    [
        GameActionItem(id: "undo", title: "戻す", systemImage: "arrow.uturn.backward", role: .undo,
                       badge: model.undosRemaining > 0 ? .count(model.undosRemaining) : .ad(gain: RewardedUndoBudget.refill),
                       isEnabled: model.canUndo) {},
        GameActionItem(id: "hint", title: "ヒント", systemImage: "lightbulb.fill", role: .hint,
                       badge: model.needsAdForHint ? .ad() : .count(model.hints.freeRemaining),
                       isEnabled: model.canUseHint) {},
    ]
}

/// 操作の段 ＋「⋯」。`GameOverflowBar` の Menu は macOS で見た目が変わるので「⋯」だけ自前で描く（寸法は同じ）。
private struct ControlRow: View {
    let model: SolitaireModel
    var body: some View {
        HStack(spacing: 8) {
            GameOverflowBar(actions: controlActions(model: model), verticalPadding: 0)
            EllipsisButton()
        }
        .padding(.vertical, 8)
    }
}

private struct BannerPlaceholder: View {
    var body: some View {
        Text("バナー広告（50pt・そのまま残す）")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color(white: 0.3))
            .frame(maxWidth: .infinity)
            .frame(height: BannerSlot.height)
            .background(Color(white: 0.82))
    }
}

/// 手数（`SolitaireView.statusBar` の写し。標準ルールなのでルール名は出ない）。
private struct MovesLabel: View {
    let model: SolitaireModel
    var body: some View {
        Label("\(model.moveCount)手", systemImage: "hand.tap.fill")
            .scaledFont(15, weight: .bold, design: .monospaced)
            .foregroundStyle(Theme.coralText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// クリア後の 1 段（`SolitaireControlsView.resultControls` の写し。高さのひな形に使う）。
private struct ResultControls: View {
    var body: some View {
        HStack(spacing: 12) {
            RecordLabel(nil).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Button {} label: { Label("次のゲーム", systemImage: "arrow.clockwise") }
                .buttonStyle(.game(.primary))
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }
}

private let clockText = "03:25"

// MARK: - 今の画面（SolitaireView.body の写し）

private struct CurrentScreen: View {
    let phone: Phone
    let model: SolitaireModel
    let services: GameServices
    let lift: Lift?
    let measure: Measure
    let prefix: String

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone, onFelt: false)
                NavHeader(title: "ソリティア", onFelt: false)
                VStack(spacing: 8) {
                    GameStatusBar {
                        MovesLabel(model: model)
                    } trailing: {
                        GameClockLabel(clockText)
                    }
                    .padding(.horizontal, Theme.pad)
                    Board(model: model, lift: lift, measure: measure, prefix: prefix)
                        .cardTable(topInset: CardTableStyle.cardTopInset)
                        .background(GeometryReader { geo in
                            let f = geo.frame(in: .named("phone"))
                            let rim = CardTableFrame.standard.insets(width: f.width)
                            let _ = {
                                measure.set("\(prefix).table_w_pt", f.width)
                                measure.set("\(prefix).table_h_pt", f.height)
                                measure.set("\(prefix).table_top_pt", f.minY)
                                measure.set("\(prefix).felt_w_pt", f.width - rim.leading - rim.trailing)
                                measure.set("\(prefix).felt_h_pt", f.height - rim.top - rim.bottom)
                                measure.set("\(prefix).felt_top_pt", f.minY + rim.top)
                            }()
                            Color.clear
                        })
                        .padding(.horizontal, CardStackLayout.boardSideInset)
                        .layoutPriority(1)
                    GameControlArea(isFinished: false, services: services) {
                        ResultControls()
                    } playing: {
                        ControlRow(model: model)
                    }
                    .padding(.horizontal, Theme.pad)
                    // HowToPlayHint は初回だけ出る（2 回目以降は無い）ので描かない。
                    Spacer(minLength: 0)
                    BannerPlaceholder().padding(.horizontal, Theme.pad)
                }
                .padding(.vertical, Theme.pad)
                Color.clear.frame(height: phone.safeBottom)
            }
        }
        .frame(width: phone.width, height: phone.height)
    }
}

// MARK: - A（全画面）

private struct FullScreenA: View {
    let phone: Phone
    let model: SolitaireModel
    let lift: Lift?
    let measure: Measure
    let prefix: String

    /// 木枠なし・角丸なしのフェルトだけ（画面全体を卓にする）。
    private static let feltOnly = CardTableFrame(
        top: .points(0), leading: .points(0), bottom: .points(0), trailing: .points(0),
        innerShadow: nil, aspectRatio: nil, cornerRadius: 0, dropShadow: false)

    var body: some View {
        let bannerBand = BannerSlot.height + 8 + phone.safeBottom
        let _ = {
            measure.set("\(prefix).felt_w_pt", phone.width)
            measure.set("\(prefix).felt_h_pt", phone.height - bannerBand)
            measure.set("\(prefix).felt_top_pt", 0)
        }()
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                CardTableSurface(frame: Self.feltOnly)
                // 画面最下部のバナー（会長の方針: A のバナーは下）。地の色の帯に置く。
                VStack(spacing: 0) {
                    BannerPlaceholder().padding(.horizontal, Theme.pad).padding(.top, 8)
                    Color.clear.frame(height: phone.safeBottom)
                }
            }
            VStack(spacing: 0) {
                StatusStrip(phone: phone, onFelt: true)
                NavHeader(title: "ソリティア", onFelt: true)
                VStack(spacing: 8) {
                    // 手数・時計は 1 行の札にまとめる（今の 44pt の帯より低い）。
                    HStack(spacing: 8) {
                        MovesLabel(model: model)
                        Spacer(minLength: 8)
                        GameClockLabel(clockText)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .popCard(corner: 10)
                    .background(GeometryReader { geo in
                        let _ = measure.set("\(prefix).status_h_pt", geo.size.height)
                        Color.clear
                    })
                    .padding(.horizontal, Theme.pad)
                    Board(model: model, lift: lift, measure: measure, prefix: prefix)
                        .environment(\.cardTableInk, .felt)
                        .padding(.horizontal, CardTableStyle.contentInset)
                    ControlRow(model: model).padding(.horizontal, Theme.pad)
                }
                .padding(.top, 8)
                .padding(.bottom, bannerBand)
            }
        }
        .frame(width: phone.width, height: phone.height)
    }
}

// MARK: - 並べて 1 枚に

private struct SideBySide<Left: View, Right: View>: View {
    let leftCaption: String
    let rightCaption: String
    let left: Left
    let right: Right
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 10) {
                Text(leftCaption).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                left.clipShape(RoundedRectangle(cornerRadius: 28)).overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            }
            VStack(spacing: 10) {
                Text(rightCaption).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                right.clipShape(RoundedRectangle(cornerRadius: 28)).overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(24)
        .background(Color(white: 0.94))
        .environment(\.colorScheme, .light)
    }
}

@Suite("#2429 レイアウト検討モック（一時）")
struct LayoutMock2429Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2429", isDirectory: true)
    }

    /// 検証済みの種で配り、勝ち筋の途中まで進めた局面（撮影用の口と同じ）。
    /// いちばん表向きが多い列の上 2 枚を持ち上げて別の列の上に運んでいる最中にする。
    @MainActor
    private static func makeModel() -> (SolitaireModel, GameServices, Lift?) {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        // 129 は `solitaireVerifiedSeeds` にある種（検証済み以外だと勝ち筋が無く、進めた局面にならない）。
        let model = SolitaireModel(services: services, seed: 129)
        model.applyPreviewProgressForTesting()
        // 「戻す」が押せる状態にはなっている（勝ち筋を進めた手が moves に入る）。
        let piles = model.board.tableau
        guard let source = piles.indices.max(by: { piles[$0].faceUp.count < piles[$1].faceUp.count }),
              piles[source].faceUp.count >= 2 else { return (model, services, nil) }
        let from = piles[source].faceUp.count - 2
        let cards = Array(piles[source].faceUp[from...])
        let over = (source + 3) % SolitaireBoard.pileCount
        return (model, services, Lift(pile: source, from: from, cards: cards, overPile: over))
    }

    @MainActor
    private static func write(_ view: some View, scale: CGFloat, name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent(name)
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        print("wrote \(url.path) \(image.width)x\(image.height)")
    }

    @Test("今 vs A を描いて寸法を書き出す")
    @MainActor
    func render() throws {
        NSApp?.appearance = NSAppearance(named: .aqua)
        var all: [String: [String: Double]] = [:]
        for phone in phones {
            let (model, services, lift) = Self.makeModel()
            #expect(lift != nil, "持ち上げる札が見つからない")
            let measure = Measure()
            let cur = "\(phone.name)_cur", a = "\(phone.name)_a"
            let view = SideBySide(
                leftCaption: "今",
                rightCaption: "A 全画面",
                left: CurrentScreen(phone: phone, model: model, services: services, lift: lift, measure: measure, prefix: cur)
                    .coordinateSpace(name: "phone"),
                right: FullScreenA(phone: phone, model: model, lift: lift, measure: measure, prefix: a)
                    .coordinateSpace(name: "phone")
            )
            try Self.write(view, scale: phone.scale, name: "\(phone.name)_solitaire_cur_vs_a.png")
            for (k, v) in measure.values {
                let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                all[parts[0], default: [:]][parts[1]] = v
            }
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.outDir.appendingPathComponent("measure_solitaire.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
