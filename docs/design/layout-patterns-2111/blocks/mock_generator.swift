// #2435 のレイアウト検討モック（ブロック崩し・今 vs A）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/GameBlocksTests/` にコピーし、
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2435
// で `<出力先>/mock2435/` に PNG 4 枚と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 実物の部品（BlocksField の盤面データ・BlocksPalette の配色・popCard・RecommendationArea・scaledFont / themeCaption）を
// そのまま使い、SpriteKit が描く盤だけ Canvas に写し、ナビバー・ステータスバー・バナーは見た目を写して描いている。
// 画面は `BlocksView.body` の写し（発射前と 1 面途中の 2 局面）。#2427（麻雀ソリティア）以降の兄弟 Issue の生成器と同じ型。
// 終わったらコピーは消す（コミットしない）。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreTestSupport
@testable import GameBlocks

private struct Phone {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let scale: CGFloat
    /// iOS 26 のナビバーの高さ。iPhone 17 は 54pt（実スクショ ip17_spiderzoom_v2cur.png の実測: コンテンツ開始 = 62 + 54 = 116pt）、
    /// iPhone SE は 44pt（`BlocksLayoutTests.devices` の実機プローブ〔盤に使える高さ SE 338.5pt・iPhone 17 Pro 459.7pt〕に
    /// この生成器の「今」の盤の枠〔盤 ＋ 操作面〕を合わせると、SE だけ 54pt では 9.5pt 足りず 44pt でぴたり合う）。
    let navBarHeight: CGFloat
}

private let phones = [
    Phone(name: "ip17", width: 402, height: 874, safeTop: 62, safeBottom: 34, scale: 3, navBarHeight: 54),
    Phone(name: "se3", width: 375, height: 667, safeTop: 20, safeBottom: 0, scale: 2, navBarHeight: 44),
]

/// 描画中に GeometryReader から寸法を書き留める器。
private final class Measure: @unchecked Sendable {
    var values: [String: Double] = [:]
    func set(_ key: String, _ value: CGFloat) { values[key] = (Double(value) * 100).rounded() / 100 }
}

private func swiftColor(_ hex: UInt32) -> Color { Color(nsColor: BlocksPalette.color(hex)) }

// MARK: - 盤（BlocksScene が SpriteKit で描くものを Canvas に写す）

/// 盤。`BlocksField` の状態（ブロック・パドル・球・落下中のアイテム）を `BlocksScene` と同じ座標変換（左下原点・
/// `scaleMode = .aspectFit`）と同じ配色で 1 枚の Canvas に描く。
private struct BoardCanvas: View {
    let field: BlocksField
    let measure: Measure
    let prefix: String

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / BlocksField.Metrics.width
            let f = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).board_w_pt", geo.size.width)
                measure.set("\(prefix).board_h_pt", geo.size.height)
                measure.set("\(prefix).board_top_pt", f.minY)
                measure.set("\(prefix).board_left_pt", f.minX)
                measure.set("\(prefix).pt_per_unit", unit)
                measure.set("\(prefix).block_w_pt", BlocksField.Metrics.blockWidth * unit)
                measure.set("\(prefix).block_h_pt", BlocksField.Metrics.blockHeight * unit)
                measure.set("\(prefix).paddle_w_pt", field.paddleWidth * unit)
                measure.set("\(prefix).paddle_h_pt", BlocksField.Metrics.paddleHeight * unit)
                measure.set("\(prefix).ball_d_pt", BlocksField.Metrics.ballRadius * 2 * unit)
            }()
            Canvas { ctx, size in
                let u = size.width / BlocksField.Metrics.width
                // 抽象単位（左下原点）→ pt（左上原点）。
                func point(_ x: Double, _ y: Double) -> CGPoint {
                    CGPoint(x: x * u, y: (BlocksField.Metrics.height - y) * u)
                }
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(swiftColor(BlocksPalette.field)))
                // ブロック。実寸より 0.6 単位小さく描く（BlocksScene.rebuildBlocks と同じ）。
                for row in 0..<field.rowCount {
                    for column in 0..<BlocksField.Metrics.columns {
                        guard let block = field.block(row: row, column: column) else { continue }
                        let r = BlocksField.blockRect(row: row, column: column)
                        let rect = CGRect(x: (r.minX + 0.3) * u, y: (BlocksField.Metrics.height - r.maxY + 0.3) * u,
                                          width: (r.maxX - r.minX - 0.6) * u, height: (r.maxY - r.minY - 0.6) * u)
                        ctx.fill(Path(rect), with: .color(Color(nsColor: BlocksPalette.blockColor(block, row: row))))
                    }
                }
                // 落下中のアイテム（地の色 ＋ 形の印）。
                for item in field.items {
                    let w = BlocksField.Metrics.itemWidth * u, h = BlocksField.Metrics.itemHeight * u
                    let c = point(item.x, item.y)
                    let body = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
                    ctx.fill(Path(roundedRect: body, cornerRadius: h / 2), with: .color(swiftColor(BlocksPalette.itemColor(item.kind))))
                    let mark = swiftColor(BlocksPalette.itemMark)
                    switch item.kind {
                    case .widePaddle:
                        ctx.fill(Path(CGRect(x: c.x - w * 0.31, y: c.y - h * 0.13, width: w * 0.62, height: h * 0.26)), with: .color(mark))
                    case .multiBall:
                        for offset in [-1.0, 0, 1.0] {
                            let r = h * 0.17
                            ctx.fill(Path(ellipseIn: CGRect(x: c.x + offset * w * 0.22 - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(mark))
                        }
                    }
                }
                // パドル（伸長中は横だけ伸びる）。
                let pw = field.paddleWidth * u, ph = BlocksField.Metrics.paddleHeight * u
                let pc = point(field.paddleX, BlocksField.Metrics.paddleY)
                ctx.fill(Path(roundedRect: CGRect(x: pc.x - pw / 2, y: pc.y - ph / 2, width: pw, height: ph), cornerRadius: ph / 2),
                         with: .color(swiftColor(BlocksPalette.paddle)))
                // 球。
                for ball in field.balls {
                    let r = BlocksField.Metrics.ballRadius * u
                    let c = point(ball.x, ball.y)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .color(swiftColor(BlocksPalette.ball)))
                }
            }
        }
    }
}

/// 発射前の「タップで発射」の札（`BlocksView.readyOverlay` の写し）。下端からの距離は盤の大きさに比例する（#597）。
private struct ReadyOverlay: View {
    let boardWidth: CGFloat
    var body: some View {
        let unit = BlocksField.Metrics.pointsPerUnit(boardWidth: Double(boardWidth))
        VStack {
            Spacer()
            Label("タップで発射", systemImage: "hand.tap.fill")
                .themeCaption(13)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.35)))
                .padding(.bottom, BlocksField.Metrics.readyHintClearance * unit)
        }
    }
}

/// 盤の枠（`BlocksView.playfield` の写し）。正方形・角丸・`layoutPriority(1)` で余った縦を先取りする。
private struct Playfield: View {
    let model: BlocksModel
    let measure: Measure
    let prefix: String
    var body: some View {
        GeometryReader { geo in
            ZStack {
                BoardCanvas(field: model.field, measure: measure, prefix: prefix)
                if model.phase == .ready { ReadyOverlay(boardWidth: geo.size.width) }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        }
        .aspectRatio(BlocksField.Metrics.aspectRatio, contentMode: .fit)
        .layoutPriority(1)
    }
}

// MARK: - 今の画面の部品（BlocksView の写し）

private struct Lives: View {
    let count: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(0, count), id: \.self) { _ in
                Image(systemName: "heart.fill")
                    .scaledFont(12)
                    .foregroundStyle(Theme.coralText)
            }
        }
    }
}

/// 今のヘッダー札（スコア 2 行 ＋ ステージ・残機）。`BlocksView.header` の写し。
private struct HeaderCard: View {
    let model: BlocksModel
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "スコア")
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.score)")
                    .scaledFont(28, weight: .heavy, design: .rounded).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: "ステージ \(model.stageNumber) / \(BlocksRules.stageCount)")
                    .themeCaption(12)
                    .foregroundStyle(Theme.inkSub)
                Lives(count: model.lives)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).header_h_pt", geo.size.height)
            Color.clear
        })
    }
}

/// 一時停止ボタン（`BlocksView.pauseButton` の写し・44pt）。
private struct PauseButton: View {
    var body: some View {
        Image(systemName: "pause.fill")
            .scaledFont(18, weight: .bold)
            .frame(width: BlocksView.pauseButtonSide, height: BlocksView.pauseButtonSide)
            .background(Circle().fill(Theme.Fill.coral))
            .foregroundStyle(Theme.onAccent)
    }
}

/// 盤の下の操作の行（レコメンド枠 ＋ 一時停止）。`BlocksView.controlRow` の写し。高さは `RecommendationArea` のひな形で決まる。
private struct ControlRow: View {
    let services: GameServices
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RecommendationArea(services: services, isFinished: false)
            PauseButton()
        }
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).control_h_pt", geo.size.height)
            Color.clear
        })
    }
}

/// 盤の下の操作面（`BlocksView.touchPad` の写し）。実物は見えないが、モックでは余った高さがどこへ行くかを示すため
/// 薄い破線と注記を重ねる（30pt 未満なら注記は出さない）。
private struct TouchPad: View {
    let measure: Measure
    let prefix: String
    var body: some View {
        GeometryReader { geo in
            let _ = measure.set("\(prefix).touchpad_h_pt", geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundStyle(Theme.inkSub.opacity(0.35))
                if geo.size.height >= 30 {
                    Text(verbatim: "操作面（なぞるとパドルが動く・実際は見えない）\(Int(geo.size.height.rounded()))pt")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSub.opacity(0.7))
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - 共通部品（ステータスバー・ナビバー・バナー）

private struct StatusStrip: View {
    let phone: Phone
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
        .foregroundStyle(Theme.ink)
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

/// iOS 26 の「戻る ＋ ゲーム名 ＋ 右のアイコン群（？・＋）」。ブロック崩しの新規は `.restart` だが、絵柄は v1.1.13 から
/// 全種類 `plus.circle.fill`（#2370）、色は `Theme.coralText`（#2377）。
private struct NavHeader: View {
    let phone: Phone
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            GlassCircle { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.coralText) }
            Spacer(minLength: 0)
            Text(verbatim: title)
                .themeBody(20, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            HStack(spacing: 24) {
                Image(systemName: "questionmark.circle")
                Image(systemName: "plus.circle.fill")
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.coralText)
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(Capsule().fill(Theme.surface).shadow(color: Theme.cardShadow, radius: 8, y: 3))
        }
        .padding(.horizontal, 16)
        .frame(height: phone.navBarHeight)
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

// MARK: - 今の画面（BlocksView.body の写し）

private struct CurrentScreen: View {
    let phone: Phone
    let model: BlocksModel
    let services: GameServices
    let measure: Measure
    let prefix: String

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader(phone: phone, title: "ブロック崩し")
                VStack(spacing: 14) {
                    HeaderCard(model: model, measure: measure, prefix: prefix)
                    Playfield(model: model, measure: measure, prefix: prefix)
                    // HowToPlayHint（初回だけ 1 行のミニガイド）は 2 回目以降は出ないので描かない。
                    ControlRow(services: services, measure: measure, prefix: prefix)
                    TouchPad(measure: measure, prefix: prefix)
                    BannerPlaceholder()
                }
                .padding(Theme.pad)
                Color.clear.frame(height: phone.safeBottom)
            }
        }
        .frame(width: phone.width, height: phone.height)
    }
}

// MARK: - A（全画面）

/// スコア・ステージ・残機を 1 行の札にまとめる（会長の方針: 手数・点数などの表示は 1 行の札に）。
private struct StatusPill: View {
    let model: BlocksModel
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "スコア")
                .scaledFont(11, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.inkSub)
            Text("\(model.score)")
                .scaledFont(16, weight: .heavy, design: .rounded).monospacedDigit()
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Text(verbatim: "ステージ \(model.stageNumber) / \(BlocksRules.stageCount)")
                .themeCaption(12)
                .foregroundStyle(Theme.inkSub)
            Lives(count: model.lives)
        }
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .popCard(corner: 10)
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).status_h_pt", geo.size.height)
            Color.clear
        })
    }
}

private struct FullScreenA: View {
    let phone: Phone
    let model: BlocksModel
    let services: GameServices
    let measure: Measure
    let prefix: String

    /// 左右の余白。今の 16pt から 8pt に詰める（兄弟 Issue の A と同じ）。盤は正方形なので、増えた幅 16pt がそのまま盤の一辺に乗る。
    static let sideInset: CGFloat = 8

    var body: some View {
        let _ = measure.set("\(prefix).banner_band_pt", BannerSlot.height + 8 + phone.safeBottom)
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader(phone: phone, title: "ブロック崩し")
                VStack(spacing: 8) {
                    StatusPill(model: model, measure: measure, prefix: prefix)
                    Playfield(model: model, measure: measure, prefix: prefix)
                    // 一時停止とレコメンド枠の行は今のまま残す（盤は正方形で幅で頭打ちになるので、この行を無くしても盤は大きくならない）。
                    ControlRow(services: services, measure: measure, prefix: prefix)
                    TouchPad(measure: measure, prefix: prefix)
                }
                .padding(.horizontal, Self.sideInset)
                .padding(.top, 8)
                .padding(.bottom, 8)
                // 画面最下部のバナー（会長の方針: A のバナーは下）。
                BannerPlaceholder().padding(.horizontal, Theme.pad)
                Color.clear.frame(height: phone.safeBottom)
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
                Text(verbatim: leftCaption).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                left.clipShape(RoundedRectangle(cornerRadius: 28)).overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            }
            VStack(spacing: 10) {
                Text(verbatim: rightCaption).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                right.clipShape(RoundedRectangle(cornerRadius: 28)).overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(24)
        .background(Color(white: 0.94))
        .environment(\.colorScheme, .light)
    }
}

// MARK: - 局面を作る

private enum Moment: String { case ready, playing }

@MainActor
private func makeModel(scene: Moment) -> (BlocksModel, GameServices) {
    let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
    let model = BlocksModel(services: services)
    switch scene {
    case .ready:
        // 開いた直後（1 面・発射前・球はパドルの上）。
        break
    case .playing:
        // 2 面に入った直後: 撮影用シナリオ「playing」（1 面で発射して 14 個壊す・スコア 140）のあと 2 面（市松・23 個）を始め、
        // 発射して球を盤の中ほどに置き、パドルを少し左へ。1 面は 2 段 18 個しか無く、14 個壊した画では盤がほぼ空になるため。
        model.applyDebugScenario("playing")
        model.applyDebugScenario("stage:2")
        model.launch()
        model.movePaddle(to: 40)
        model.placeBallForTesting(x: 61, y: 47, vx: 30, vy: 45)
    }
    return (model, services)
}

@Suite("#2435 レイアウト検討モック（一時）")
struct LayoutMock2435Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2435", isDirectory: true)
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
            for scene in [Moment.ready, .playing] {
                let (model, services) = makeModel(scene: scene)
                print("\(phone.name) \(scene): phase \(model.phase) score \(model.score) lives \(model.lives) stage \(model.stageNumber) " +
                      "remaining \(model.field.remainingBreakableCount) balls \(model.field.balls) paddle \(model.field.paddleX) items \(model.field.items.count)")
                let measure = Measure()
                let cur = "\(phone.name)_\(scene.rawValue)_cur", a = "\(phone.name)_\(scene.rawValue)_a"
                let view = SideBySide(
                    leftCaption: "今（v1.1.13）",
                    rightCaption: "A 全画面",
                    left: CurrentScreen(phone: phone, model: model, services: services, measure: measure, prefix: cur)
                        .coordinateSpace(name: "phone"),
                    right: FullScreenA(phone: phone, model: model, services: services, measure: measure, prefix: a)
                        .coordinateSpace(name: "phone")
                )
                try Self.write(view, scale: phone.scale, name: "\(phone.name)_blocks_\(scene.rawValue)_cur_vs_a.png")
                for (k, v) in measure.values {
                    let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                    all[parts[0], default: [:]][parts[1]] = v
                }
                // 派生値: 盤に使える枠（盤 ＋ 操作面。操作面だけが伸び縮みする）と、頭打ちの向き・左右の余白を 0 にしたときの盤の一辺。
                for (prefix, sideInset) in [(cur, Theme.pad), (a, FullScreenA.sideInset)] {
                    guard var m = all[prefix], let bw = m["board_w_pt"], let bh = m["board_h_pt"], let tp = m["touchpad_h_pt"] else { continue }
                    let availW = Double(phone.width - sideInset * 2)
                    m["avail_w_pt"] = availW
                    m["board_slot_h_pt"] = bh + tp
                    m["limited_by"] = bw < availW - 0.5 ? 1 : 0  // 1 = 高さで頭打ち（横幅が余る）, 0 = 幅で頭打ち
                    m["width_use_ratio"] = (bw / availW * 1000).rounded() / 1000
                    m["board_w_if_fullbleed_pt"] = BlocksField.Metrics.boardSize(availableWidth: Double(phone.width), availableHeight: bh + tp).width
                    all[prefix] = m
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.outDir.appendingPathComponent("measure_blocks.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
