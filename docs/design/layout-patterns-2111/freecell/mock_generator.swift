// #2428 のレイアウト検討モック（フリーセル・今 vs A）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/GameFreeCellTests/` にコピーし、
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2428
// で `<出力先>/mock2428/` に PNG 4 枚と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 実物の部品（FreeCellCardBody・CardSlot・GameStatusBar・GameOverflowBar・CardTableSurface・GameControlArea）をそのまま使い、
// ナビバー・ステータスバー・バナーだけ見た目を写して描いている。終わったらコピーは消す（コミットしない）。
// 型は #2427（麻雀ソリティア）の `docs/design/layout-patterns-2111/mahjong/mock_generator.swift` と同じ。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreTestSupport
@testable import GameFreeCell

private typealias Metrics = FreeCellMetrics

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

// MARK: - 盤

/// 上段（フリーセル 4 + 組札 4）。`FreeCellView.topRow` の写し（ジェスチャ・読み上げ無し）。
private struct TopRow: View {
    let model: FreeCellModel
    let metrics: PlayingCardMetrics

    var body: some View {
        HStack(spacing: Metrics.columnGap) {
            ForEach(0..<FreeCellBoard.cellCount, id: \.self) { cell in
                if let card = model.board.cells[cell] {
                    FreeCellCardBody(card: card, isSelected: model.selection == .cell(cell),
                                     coveredIndex: nil, metrics: metrics)
                } else {
                    CardSlot(metrics: metrics, systemImage: "tray")
                }
            }
            ForEach(PlayingCardSuit.allCases, id: \.rawValue) { suit in
                let rank = model.board.foundations[suit.rawValue]
                if rank > 0 {
                    FreeCellCardBody(card: FreeCellCard(suit, rank), isSelected: false,
                                     coveredIndex: nil, metrics: metrics)
                } else {
                    CardSlot(metrics: metrics, suitSymbol: suit.symbol)
                }
            }
        }
        .overlay {
            CardTableInkReader { ink in
                Capsule().fill(ink.divider).frame(width: 2.5).padding(.vertical, 2)
            }
        }
    }
}

/// 場札 8 列。`FreeCellView.tableau` / `pileView` の写し。
private struct Tableau: View {
    let model: FreeCellModel
    let metrics: PlayingCardMetrics
    let stack: CardStackLayout

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.columnGap) {
            ForEach(0..<FreeCellBoard.pileCount, id: \.self) { pile in
                let column = model.board.tableau[pile]
                let step = stack.faceUpStep
                let height = Metrics.pileHeight(cardCount: column.count, cardHeight: metrics.height, step: step)
                ZStack(alignment: .top) {
                    if column.isEmpty {
                        CardSlot(metrics: metrics, systemImage: "square.dashed")
                    } else {
                        Color.clear.frame(width: metrics.width, height: height)
                    }
                    ForEach(Array(column.enumerated()), id: \.element.id) { index, card in
                        FreeCellCardBody(
                            card: card,
                            isSelected: model.selection == .tableau(pile: pile, cardIndex: index),
                            coveredIndex: index < column.count - 1 ? stack.index : nil,
                            metrics: metrics
                        )
                        .padding(.top, CGFloat(index) * step)
                    }
                }
                .frame(width: metrics.width, height: max(height, stack.reachHeight), alignment: .top)
            }
        }
    }
}

/// 盤（卓の内側）。`FreeCellView.board` の写し。ScrollView は ImageRenderer で白紙になるので、
/// 等倍は中央寄せ・拡大は左上寄せ（2 軸スクロールの初期位置）で `clipped` にして代替。
private struct Board: View {
    let model: FreeCellModel
    let zoomed: Bool
    let measure: Measure
    let prefix: String

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let width = zoomed
                ? Metrics.zoomedCardWidth(availableWidth: size.width)
                : Metrics.cardWidth(availableWidth: size.width)
            let metrics = Metrics.faceMetrics(width: width)
            let stack = Metrics.stackLayout(
                cardWidth: metrics.width, cardHeight: metrics.height,
                boardHeight: size.height, pileCounts: model.board.tableau.map(\.count))
            let boardWidth = Metrics.boardWidth(cardWidth: width)
            let longest = model.board.tableau.map(\.count).max() ?? 0
            let contentHeight = Metrics.boardTopPadding + metrics.height + FreeCellMotion.topRowSpacing
                + Metrics.pileHeight(cardCount: longest, cardHeight: metrics.height, step: stack.faceUpStep)
            let frame = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).board_w_pt", size.width)
                measure.set("\(prefix).board_h_pt", size.height)
                measure.set("\(prefix).board_top_pt", frame.minY)
                measure.set("\(prefix).card_w_pt", metrics.width)
                measure.set("\(prefix).card_h_pt", metrics.height)
                measure.set("\(prefix).step_pt", stack.faceUpStep)
                measure.set("\(prefix).tableau_h_pt", stack.reachHeight)
                measure.set("\(prefix).longest_pile_h_pt",
                            Metrics.pileHeight(cardCount: longest, cardHeight: metrics.height, step: stack.faceUpStep))
                measure.set("\(prefix).content_w_pt", boardWidth)
                measure.set("\(prefix).content_h_pt", contentHeight)
                let visW = min(size.width, boardWidth), visH = min(size.height, contentHeight)
                measure.set("\(prefix).visible_ratio", (visW * visH) / (boardWidth * contentHeight))
            }()
            VStack(spacing: FreeCellMotion.topRowSpacing) {
                TopRow(model: model, metrics: metrics)
                Tableau(model: model, metrics: metrics, stack: stack)
            }
            .frame(width: boardWidth)
            .padding(.top, Metrics.boardTopPadding)
            .frame(width: size.width, height: size.height, alignment: zoomed ? .topLeading : .top)
            .clipped()
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

/// iOS 26 の「戻る ＋ ゲーム名 ＋ 右のアイコン群」。
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

@MainActor
private func controlActions(model: FreeCellModel) -> [GameActionItem] {
    [
        GameActionItem(id: "undo", title: "戻す", systemImage: "arrow.uturn.backward", role: .undo,
                       badge: .count(model.undosRemaining), isEnabled: model.canUndo) {},
        GameActionItem(id: "hint", title: "ヒント", systemImage: "lightbulb.fill", role: .hint,
                       badge: .count(model.hints.freeRemaining)) {},
    ]
}

/// 操作の段 ＋「⋯」（拡大・自動で上がる）。`GameOverflowBar` の Menu は macOS で見た目が変わるので「⋯」だけ自前で描く（寸法は同じ）。
private struct ControlRow: View {
    let model: FreeCellModel
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

/// 手数・配札番号・時計（`FreeCellView.statusReadout` の写し）。
private struct StatusContent: View {
    let model: FreeCellModel
    var body: some View {
        HStack(spacing: 8) {
            Label("\(model.moveCount)手", systemImage: "hand.tap.fill")
                .scaledFont(15, weight: .bold, design: .monospaced)
                .foregroundStyle(Theme.coralText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(verbatim: "配札 #\(String(model.dealNumber))")
                .scaledFont(10, weight: .bold, design: .monospaced)
                .foregroundStyle(Theme.inkSub)
            GameClockLabel("02:17")
        }
    }
}

/// クリア後の 1 段（`FreeCellView.resultControls` の写し。高さのひな形に使う）。
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

// MARK: - 今の画面

private struct CurrentScreen: View {
    let phone: Phone
    let model: FreeCellModel
    let services: GameServices
    let zoomed: Bool
    let measure: Measure
    let prefix: String

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone, onFelt: false)
                NavHeader(title: "フリーセル", onFelt: false)
                // `FreeCellView.body` の写し: 帯・段・バナーは 16pt、盤だけ 4pt まで詰める。
                VStack(spacing: 8) {
                    GameStatusBar {
                        StatusContent(model: model)
                    } trailing: {
                        EmptyView()
                    }
                    .padding(.horizontal, Theme.pad)
                    Board(model: model, zoomed: zoomed, measure: measure, prefix: prefix)
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
                        .padding(.horizontal, Metrics.boardSideInset)
                        .layoutPriority(1)
                    GameControlArea(isFinished: false, services: services) {
                        ResultControls()
                    } playing: {
                        ControlRow(model: model)
                    }
                    .padding(.horizontal, Theme.pad)
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
    let model: FreeCellModel
    let zoomed: Bool
    let measure: Measure
    let prefix: String

    /// 木枠なし・角丸なしのフェルトだけ（画面全体を卓にする）。
    private static let feltOnly = CardTableFrame(
        top: .points(0), leading: .points(0), bottom: .points(0), trailing: .points(0),
        innerShadow: nil, aspectRatio: nil, cornerRadius: 0, dropShadow: false)

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                CardTableSurface(frame: Self.feltOnly)
                    .background(GeometryReader { geo in
                        let f = geo.frame(in: .named("phone"))
                        let _ = {
                            measure.set("\(prefix).felt_w_pt", f.width)
                            measure.set("\(prefix).felt_h_pt", f.height)
                            measure.set("\(prefix).felt_top_pt", f.minY)
                        }()
                        Color.clear
                    })
                // 画面最下部のバナー（会長の方針: A のバナーは下）。地の色の帯に置く。
                VStack(spacing: 0) {
                    BannerPlaceholder().padding(.horizontal, Theme.pad).padding(.top, 8)
                    Color.clear.frame(height: phone.safeBottom)
                }
            }
            VStack(spacing: 0) {
                StatusStrip(phone: phone, onFelt: true)
                NavHeader(title: "フリーセル", onFelt: true)
                VStack(spacing: 8) {
                    // 手数・配札・時計は 1 行の札にまとめる（今の 44pt の帯より低い）。
                    HStack(spacing: 8) {
                        StatusContent(model: model)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .popCard(corner: 10)
                    .background(GeometryReader { geo in
                        let _ = measure.set("\(prefix).status_h_pt", geo.size.height)
                        Color.clear
                    })
                    .padding(.horizontal, Theme.pad)
                    Board(model: model, zoomed: zoomed, measure: measure, prefix: prefix)
                        .environment(\.cardTableInk, .felt)
                        .padding(.horizontal, CardTableStyle.contentInset)
                    ControlRow(model: model).padding(.horizontal, Theme.pad)
                }
                .padding(.top, 8)
                .padding(.bottom, BannerSlot.height + 8 + phone.safeBottom)
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

@Suite("#2428 レイアウト検討モック（一時）")
struct LayoutMock2428Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2428", isDirectory: true)
    }

    @MainActor
    private static func makeModel() -> (FreeCellModel, GameServices) {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        // 検証済みの種で、勝ち筋の前半まで進めた局面（撮影用の `-freecellMidgame` と同じ作り方）。
        let model = FreeCellModel(services: services, seed: freeCellVerifiedSeeds[0])
        model.applyPreviewProgressForTesting(ratio: 0.35)
        // いちばん長い列の、動かせる並びの先頭を 1 枚選んだ状態にする（ドラッグで持ち上げる直前の見え方）。
        if let pile = model.board.tableau.indices.max(by: { model.board.tableau[$0].count < model.board.tableau[$1].count }),
           !model.board.tableau[pile].isEmpty {
            let column = model.board.tableau[pile]
            var index = column.count - 1
            while index > 0, model.board.isOrderedRun(pile: pile, from: index - 1) { index -= 1 }
            model.tapPile(pile, cardIndex: index)
        }
        return (model, services)
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
            for zoomed in [false, true] {
                let (model, services) = Self.makeModel()
                let measure = Measure()
                let mode = zoomed ? "zoom" : "whole"
                // JSON の鍵は `measure_mahjong.json` と同じ並び（<端末>_<今|a>_<表示>）。
                let cur = "\(phone.name)_cur_\(mode)", a = "\(phone.name)_a_\(mode)"
                let view = SideBySide(
                    leftCaption: "今（\(zoomed ? "拡大" : "等倍")）",
                    rightCaption: "A 全画面（\(zoomed ? "拡大" : "等倍")）",
                    left: CurrentScreen(phone: phone, model: model, services: services, zoomed: zoomed, measure: measure, prefix: cur)
                        .coordinateSpace(name: "phone"),
                    right: FullScreenA(phone: phone, model: model, zoomed: zoomed, measure: measure, prefix: a)
                        .coordinateSpace(name: "phone")
                )
                try Self.write(view, scale: phone.scale, name: "\(phone.name)_freecell_\(mode)_cur_vs_a.png")
                for (k, v) in measure.values {
                    let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                    all[parts[0], default: [:]][parts[1]] = v
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.outDir.appendingPathComponent("measure_freecell.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
