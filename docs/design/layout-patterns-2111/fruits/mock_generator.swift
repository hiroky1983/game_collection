// #2437 のレイアウト検討モック（おじさんの盆栽・今 vs A）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/GameFruitsTests/` にコピーし、`release/v1.1.13` の上で
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2437
// で `<出力先>/mock2437/` に PNG 4 枚（2 局面 × 2 端末）と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 「今」は `FruitsView.body` の写し（ヘッダーの札・縁側 `BonsaiEngawaBoards`・おじさん `BonsaiOjisanLayer`・`RecommendationArea` は
// 実物の部品。庭は SpriteKit（`FruitsScene`）が描くため写らないので、実物の `FruitField`（盆栽の位置）・`BonsaiArt`（絵と置き方）・
// `FruitsPalette`（配色）から同じ座標変換で Canvas と `BonsaiIcon` に描き直す。ナビバー・ステータスバー・バナーは見た目を写す）。
// A は同じ中身を「外周 8pt・ヘッダーの札を 1 行の札に・レコメンド枠の確保なし・バナーは最下部」に置き直したもの。
// 局面は実物の `FruitsModel` を種から自動で落として作る（#2427〜#2435 の生成器と同じ型）。終わったらコピーは消す（コミットしない）。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreTestSupport
@testable import GameFruits

private struct Phone {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let scale: CGFloat
    /// iOS 26 のナビバーの高さ。iPhone 17 は 54pt（実スクショ ip17_spiderzoom_v2cur.png の実測: コンテンツ開始 = 62 + 54 = 116pt）、
    /// iPhone SE は 44pt（ブロック崩し #2435 のモックと同じ。`BlocksLayoutTests.devices` の実機プローブ〔盤に使える高さ SE 338.5pt〕に
    /// 合うのは 44pt のほう。麻雀ソリティア〜ルーレットのモックは SE も 54pt で描いている）。
    let navBarHeight: CGFloat
    /// 今の画面で中身に使える高さ（ナビバーの下から画面の下の安全域まで）。
    var contentHeight: CGFloat { height - safeTop - navBarHeight - safeBottom }
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

/// A の寸法。
private enum LayoutA {
    /// 画面の左右の余白（今の `Theme.pad` 16 から詰める。兄弟 Issue の A と同じ）。
    static let sideInset: CGFloat = 8
    /// 部品のあいだの縦の間隔と、上下の余白。
    static let spacing: CGFloat = 8
}

/// `FruitsPalette`（SpriteKit の配色・`SKColor`）を SwiftUI の色に。
private func paletteColor(_ hex: UInt32, alpha: CGFloat = 1) -> Color {
    Color(nsColor: FruitsPalette.color(hex, alpha: alpha))
}

/// 縁側＋庭の枠（幅 / 高さ = 100 / 142）を `available` に収めたときの大きさ（`.aspectRatio(_:contentMode: .fit)` の計算そのもの）。
private func playfieldSize(availableWidth: Double, availableHeight: Double) -> (width: Double, height: Double) {
    guard availableWidth > 0, availableHeight > 0 else { return (0, 0) }
    let ratio = BonsaiEngawaLayout.aspectRatio
    let heightLimited = availableHeight * ratio
    if heightLimited <= availableWidth { return (heightLimited, availableHeight) }
    return (availableWidth, availableWidth / ratio)
}

/// 枠の位置と大きさを `phone` 座標で書き留める。
private struct FrameProbe: View {
    let measure: Measure
    let prefix: String
    let key: String
    var body: some View {
        GeometryReader { geo in
            let f = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).\(key)_w_pt", f.width)
                measure.set("\(prefix).\(key)_h_pt", f.height)
                measure.set("\(prefix).\(key)_top_pt", f.minY)
                measure.set("\(prefix).\(key)_bottom_pt", f.maxY)
            }()
            Color.clear
        }
    }
}

// MARK: - 庭（FruitsScene が SpriteKit で描くものを Canvas と BonsaiIcon に写す）

/// 庭（盤）。`FruitsScene` と同じ座標系（左下原点・盤の抽象単位 100 × 120・`scaleMode = .aspectFit`）と配色で、
/// 砂利の箒目・石・箱の縁・危険線・落とす位置の案内線を Canvas に、盆栽を `BonsaiIcon`（`BonsaiArt.spriteFrame` の位置・
/// `FruitsScene.zPosition` の重なり順）に描く。
private struct GardenCanvas: View {
    let model: FruitsModel
    let measure: Measure
    let prefix: String

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / FruitField.Metrics.width
            let f = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).garden_w_pt", geo.size.width)
                measure.set("\(prefix).garden_h_pt", geo.size.height)
                measure.set("\(prefix).garden_top_pt", f.minY)
                measure.set("\(prefix).garden_left_pt", f.minX)
                measure.set("\(prefix).pt_per_unit", unit)
                measure.set("\(prefix).sakura_d_pt", FruitKind.sakura.radius * 2 * unit)
                measure.set("\(prefix).mikan_d_pt", FruitKind.mikan.radius * 2 * unit)
                measure.set("\(prefix).kinmatsu_d_pt", FruitKind.kinmatsu.radius * 2 * unit)
                measure.set("\(prefix).deadline_from_garden_top_pt", (FruitField.Metrics.height - FruitField.Metrics.deadlineY) * unit)
                measure.set("\(prefix).deadline_to_floor_pt", FruitField.Metrics.deadlineY * unit)
            }()
            let ordered = model.field.fruits.sorted {
                FruitsScene.zPosition(for: $0.kind, bottomY: $0.y - $0.radius)
                    < FruitsScene.zPosition(for: $1.kind, bottomY: $1.y - $1.radius)
            }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let u = size.width / FruitField.Metrics.width
                    let fieldHeight = FruitField.Metrics.height
                    // 抽象単位（左下原点）→ pt（左上原点）。
                    func point(_ x: Double, _ y: Double) -> CGPoint {
                        CGPoint(x: x * u, y: (fieldHeight - y) * u)
                    }
                    // 砂利の地。
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paletteColor(FruitsPalette.box)))
                    // 箒目（`FruitsScene.addGarden`）。
                    var rake = Path()
                    for y in stride(from: 4.0, to: fieldHeight, by: 4.0) {
                        rake.move(to: point(0, y))
                        rake.addLine(to: point(FruitField.Metrics.width, y))
                    }
                    ctx.stroke(rake, with: .color(paletteColor(FruitsPalette.rake, alpha: 0.7)), lineWidth: 0.35 * u)
                    // 石。
                    for (x, y, r) in [(12.0, 6.0, 3.6), (86.0, 4.5, 2.8), (50.0, 2.5, 2.2)] {
                        let c = point(x, y)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * u, y: c.y - r * 0.6 * u, width: r * 2 * u, height: r * 1.2 * u)),
                                 with: .color(paletteColor(FruitsPalette.stone)))
                    }
                    // 箱の縁。
                    ctx.stroke(Path(CGRect(x: 0.4 * u, y: 0.4 * u, width: (FruitField.Metrics.width - 0.8) * u, height: (fieldHeight - 0.8) * u)),
                               with: .color(paletteColor(FruitsPalette.boxEdge, alpha: 0.6)), lineWidth: 0.8 * u)
                    // 危険線（点線）。盆栽が掛かっているあいだは赤く太い（`FruitsScene.applyDeadlineStyle`）。
                    var deadline = Path()
                    deadline.move(to: point(0, FruitField.Metrics.deadlineY))
                    deadline.addLine(to: point(FruitField.Metrics.width, FruitField.Metrics.deadlineY))
                    let warning = model.isOverLine
                    ctx.stroke(deadline,
                               with: .color(warning ? paletteColor(FruitsPalette.deadlineWarning) : paletteColor(FruitsPalette.deadline, alpha: 0.6)),
                               style: StrokeStyle(lineWidth: (warning ? 1.1 : 0.7) * u, dash: [2.2 * u, 1.6 * u]))
                    // 落とす位置の案内線（遊んでいるあいだは手が空でも出す）。
                    if model.phase == .playing {
                        var guide = Path()
                        guide.move(to: point(model.field.cursorX, 0.6))
                        guide.addLine(to: point(model.field.cursorX, FruitField.Metrics.spawnY))
                        ctx.stroke(guide, with: .color(paletteColor(FruitsPalette.guide, alpha: 0.45)),
                                   style: StrokeStyle(lineWidth: 0.5 * u, dash: [1.6 * u, 1.6 * u]))
                    }
                }
                ForEach(ordered, id: \.id) { fruit in
                    let frame = BonsaiArt.spriteFrame(for: fruit.kind, x: fruit.x, y: fruit.y)
                    BonsaiIcon(fruit.kind)
                        .frame(width: frame.width * unit, height: frame.height * unit)
                        .offset(x: frame.minX * unit, y: (FruitField.Metrics.height - frame.maxY) * unit)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
    }
}

/// 指の位置の印（**実物には出ない**。ドラッグ中であることを示すための注記）。落とす位置の真上・庭の中ほどに描く。
private struct FingerMark: View {
    let cursorX: Double
    let unit: CGFloat
    var body: some View {
        let x = cursorX * unit
        let y = (BonsaiEngawaLayout.height + FruitField.Metrics.height * 0.55) * unit
        ZStack {
            Circle().fill(Color.white.opacity(0.35))
            Circle().strokeBorder(Theme.inkSub.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            Text(verbatim: "指")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.inkSub)
        }
        .frame(width: 44, height: 44)
        .position(x: x, y: y)
    }
}

/// 縁側と庭を縦に積んだ 1 枚の枠（`FruitsView.playfield` の写し）。縁側＋庭の比で収め、`layoutPriority(1)` で余った縦を先取りする。
private struct Playfield: View {
    let model: FruitsModel
    let showsFinger: Bool
    let measure: Measure
    let prefix: String

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / FruitField.Metrics.width
            let f = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).playfield_w_pt", geo.size.width)
                measure.set("\(prefix).playfield_h_pt", geo.size.height)
                measure.set("\(prefix).playfield_top_pt", f.minY)
                measure.set("\(prefix).playfield_bottom_pt", f.maxY)
                measure.set("\(prefix).engawa_h_pt", BonsaiEngawaLayout.height * unit)
                measure.set("\(prefix).ojisan_h_pt", BonsaiEngawaLayout.ojisanFrame(cursorX: model.field.cursorX).height * unit)
            }()
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    BonsaiEngawaBoards()
                        .frame(height: BonsaiEngawaLayout.height * unit)
                    GardenCanvas(model: model, measure: measure, prefix: prefix)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                // おじさんと手元の盆栽は枠で切らない（実物と同じ）。
                BonsaiOjisanLayer(
                    cursorX: model.field.cursorX, heldKind: model.heldKind,
                    isNearLine: model.isNearLine, unit: unit
                )
                if showsFinger {
                    FingerMark(cursorX: model.field.cursorX, unit: unit)
                }
            }
        }
        .aspectRatio(BonsaiEngawaLayout.aspectRatio, contentMode: .fit)
        .layoutPriority(1)
    }
}

// MARK: - 今の画面の部品（FruitsView の写し）

/// 今のヘッダーの札（スコア 2 行 ＋ つぎの盆栽）。`FruitsView.header` の写し。
private struct HeaderCard: View {
    let model: FruitsModel
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("スコア"))
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                Text(verbatim: RecordFormat.number(model.score))
                    .scaledFont(28, weight: .heavy, design: .rounded).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tr("つぎ"))
                        .scaledFont(12, weight: .bold, design: .rounded)
                        .foregroundStyle(Theme.inkSub)
                    Text(model.nextKind.name)
                        .scaledFont(13, weight: .bold, design: .rounded)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                BonsaiIcon(model.nextKind)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        .background(FrameProbe(measure: measure, prefix: prefix, key: "header"))
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

/// iOS 26 の「戻る ＋ ゲーム名 ＋ 右のアイコン群（？・＋）」。盆栽の新規は `.restart` で、絵柄は v1.1.13 から
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

// MARK: - 局面

private enum Situation: String, CaseIterable {
    /// 途中・ドラッグ中: 盆栽が積み上がり（合体あり）、指で落とす位置を右へ寄せている（おじさんが付いてきて盆栽を持っている）。
    case mid
    /// 危険線に掛かった瞬間: 積み上がった盆栽が線より上に出て、線が赤く太く・おじさんがしかめ面（終局まで 1 秒以内）。
    case over
}

// MARK: - 今の画面（FruitsView.body の写し）

private struct CurrentScreen: View {
    let phone: Phone
    let model: FruitsModel
    let services: GameServices
    let scene: Situation
    let measure: Measure
    let prefix: String

    var body: some View {
        let _ = {
            measure.set("\(prefix).avail_top_pt", phone.safeTop + phone.navBarHeight)
            measure.set("\(prefix).avail_bottom_pt", phone.height - phone.safeBottom)
            measure.set("\(prefix).side_inset_pt", Theme.pad)
            measure.set("\(prefix).stack_spacing_pt", 12)
        }()
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader(phone: phone, title: tr("おじさんの盆栽"))
                VStack(spacing: 12) {
                    HeaderCard(model: model, measure: measure, prefix: prefix)
                    Playfield(model: model, showsFinger: scene == .mid, measure: measure, prefix: prefix)
                    // 初回だけ出る 1 行のミニガイド（`HowToPlayHint`）は 2 回目以降は無いので描かない。
                    RecommendationArea(services: services, isFinished: model.phase == .gameOver)
                        .background(FrameProbe(measure: measure, prefix: prefix, key: "rec"))
                    BannerPlaceholder()
                        .background(FrameProbe(measure: measure, prefix: prefix, key: "banner"))
                }
                .padding(Theme.pad)
                // NavigationStack の中身は中央寄せ（縁側＋庭が余った縦を先取りするので、実際には余りは出ない）。
                .frame(width: phone.width, height: phone.contentHeight, alignment: .center)
                .background(FrameProbe(measure: measure, prefix: prefix, key: "content"))
                Color.clear.frame(height: phone.safeBottom)
            }
        }
        .frame(width: phone.width, height: phone.height)
        .clipped()
    }
}

// MARK: - A（全画面）

/// スコアと「つぎ」を 1 行の札にまとめる（会長の方針: 手数・点数などの表示は 1 行の札に）。
private struct StatusLineA: View {
    let model: FruitsModel
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack(spacing: 8) {
            Text(tr("スコア"))
                .scaledFont(11, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.inkSub)
            Text(verbatim: RecordFormat.number(model.score))
                .scaledFont(16, weight: .heavy, design: .rounded).monospacedDigit()
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Text(tr("つぎ"))
                .scaledFont(11, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.inkSub)
            Text(model.nextKind.name)
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.ink)
            BonsaiIcon(model.nextKind)
                .frame(width: 24, height: 24)
        }
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .popCard(corner: 10)
        .background(FrameProbe(measure: measure, prefix: prefix, key: "status"))
    }
}

private struct FullScreenA: View {
    let phone: Phone
    let model: FruitsModel
    let scene: Situation
    let measure: Measure
    let prefix: String

    var body: some View {
        let bannerBand = BannerSlot.height + LayoutA.spacing + phone.safeBottom
        let _ = {
            measure.set("\(prefix).avail_top_pt", phone.safeTop + phone.navBarHeight)
            measure.set("\(prefix).avail_bottom_pt", phone.height - bannerBand)
            measure.set("\(prefix).banner_band_pt", bannerBand)
            measure.set("\(prefix).side_inset_pt", LayoutA.sideInset)
            measure.set("\(prefix).stack_spacing_pt", LayoutA.spacing)
        }()
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader(phone: phone, title: tr("おじさんの盆栽"))
                VStack(spacing: LayoutA.spacing) {
                    StatusLineA(model: model, measure: measure, prefix: prefix)
                    Playfield(model: model, showsFinger: scene == .mid, measure: measure, prefix: prefix)
                    // レコメンド枠（`RecommendationArea` が終局後のカードのために常に確保している高さ）は置かない。
                    // 終局後にカードを出す場所は共通化のときに決める論点（ソリティア #2429 と同じ扱い）。
                    // 幅で頭打ちになった端末では、余った縦はここ（盤の下）に残る。
                }
                .padding(.horizontal, LayoutA.sideInset)
                .padding(.vertical, LayoutA.spacing)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(FrameProbe(measure: measure, prefix: prefix, key: "content"))
                // 画面最下部のバナー（会長の方針: A のバナーは下）。
                BannerPlaceholder().padding(.horizontal, Theme.pad)
                    .background(FrameProbe(measure: measure, prefix: prefix, key: "banner"))
                Color.clear.frame(height: phone.safeBottom)
            }
        }
        .frame(width: phone.width, height: phone.height)
        .clipped()
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

// MARK: - 生成

@Suite("#2437 レイアウト検討モック（一時）")
struct LayoutMock2437Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2437", isDirectory: true)
    }

    /// 途中の局面で落とす位置（抽象単位）。左右に散らして自然な山にする。
    private static let dropXs: [Double] = [20, 80, 35, 65, 50, 22, 78, 40, 60, 50, 30, 70, 48, 25, 75, 55, 45, 62, 38, 50, 68, 32]
    /// ドラッグ中の指の位置（抽象単位）。
    private static let dragX: Double = 68

    /// 実物の `FruitsModel` を種から自動で落として局面を作る。
    /// - `mid`: `dropXs` の順に落として落ち着かせ、指を `dragX` へ寄せた状態。条件: 遊んでいる・盆栽を手に持っている・
    ///   合体で銀杏以上ができている・危険線に近くない。
    /// - `over`: `mid` のあと真ん中へ落とし続け、危険線より上に盆栽が出た（線が赤くなった）瞬間。条件: まだ終局していない。
    /// 条件に合う種を 2437 から順に探して固定する。
    @MainActor
    private static func makeModel(_ scene: Situation) -> (FruitsModel, GameServices, UInt64) {
        var seed: UInt64 = 2437
        while true {
            let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
            let model = FruitsModel(services: services, seed: seed)
            func settle(_ seconds: Double) {
                var elapsed = 0.0
                while elapsed < seconds {
                    model.tick(dt: 1.0 / 60)
                    elapsed += 1.0 / 60
                }
            }
            var ok = true
            for x in dropXs {
                model.moveCursor(to: x)
                settle(FruitsModel.dropCooldown + 0.1)
                guard model.canDrop else { ok = false; break }
                model.drop()
                settle(1.2)
            }
            settle(3)
            guard ok, model.phase == .playing, model.field.isSettled else { seed += 1; continue }
            switch scene {
            case .mid:
                model.moveCursor(to: dragX)
                guard model.heldKind != nil, !model.isNearLine, !model.isOverLine,
                      model.field.fruits.contains(where: { $0.kind >= .icho }) else { seed += 1; continue }
                return (model, services, seed)
            case .over:
                // 同じ山の上へ大きい盆栽（真柏・黒松・紅葉・南天）を 1 鉢ずつ落とし（中断データに足して復元する。撮影用の
                // `-simulateFruits gameover` と同じ入れ方）、危険線より上に出た瞬間（線が赤くなり、終局まで 1 秒以内）で止める。
                // 小さい盆栽を落とし続けるだけでは合体で山が崩れて線まで届かないため。
                var current = model
                var currentServices = services
                let stack: [FruitKind] = [.shinpaku, .kuromatsu, .momiji, .nanten]
                var placed = 0
                var result: FruitsModel?
                while placed < 12 {
                    let kind = stack[placed % stack.count]
                    var fruits = current.field.fruits
                    let nextID = (fruits.map(\.id).max() ?? -1) + 1
                    let x = FruitField.Metrics.clampedX(50 + Double(placed % 3 - 1) * 12, radius: kind.radius)
                    fruits.append(Fruit(id: nextID, kind: kind, x: x, y: FruitField.Metrics.spawnY))
                    let snapshot = FruitsSnapshot(
                        fruits: fruits, cursorX: 50, score: current.score,
                        heldKind: current.heldKind ?? current.nextKind, nextKind: current.nextKind,
                        continueUsed: false, seed: seed, drawCount: 0,
                        dropCount: current.dropCount + 1, hasMadeKinmatsu: current.hasMadeKinmatsu
                    )
                    let store = MemorySnapshotStore()
                    guard (try? store.save(snapshot, for: FruitsModel.gameID)) != nil else { break }
                    let restoredServices = GameServices(snapshots: store, ads: NoopAdService())
                    let restored = FruitsModel(services: restoredServices)
                    var elapsed = 0.0
                    while elapsed < 3.0, !restored.isOverLine, restored.phase == .playing,
                          !(elapsed > 1.0 && restored.field.isSettled) {
                        restored.tick(dt: 1.0 / 60)
                        elapsed += 1.0 / 60
                    }
                    if restored.isOverLine, restored.phase == .playing {
                        result = restored
                        currentServices = restoredServices
                        break
                    }
                    guard restored.phase == .playing else { break }
                    current = restored
                    currentServices = restoredServices
                    placed += 1
                }
                guard let over = result, over.isNearLine else { seed += 1; continue }
                return (over, currentServices, seed)
            }
        }
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
            for scene in Situation.allCases {
                let (model, services, seed) = Self.makeModel(scene)
                let kinds = model.field.fruits.map { "\($0.kind)" }.joined(separator: ",")
                print("\(phone.name) \(scene): seed \(seed) phase \(model.phase) score \(model.score) count \(model.fruitCount) " +
                      "held \(String(describing: model.heldKind)) next \(model.nextKind) cursor \(model.field.cursorX) " +
                      "overLine \(model.isOverLine) nearLine \(model.isNearLine) highest \(model.field.highestTop) kinds [\(kinds)]")
                let measure = Measure()
                let cur = "\(phone.name)_\(scene.rawValue)_cur", a = "\(phone.name)_\(scene.rawValue)_a"
                let view = SideBySide(
                    leftCaption: "今（v1.1.13）",
                    rightCaption: "A 全画面",
                    left: CurrentScreen(phone: phone, model: model, services: services, scene: scene, measure: measure, prefix: cur)
                        .coordinateSpace(name: "phone"),
                    right: FullScreenA(phone: phone, model: model, scene: scene, measure: measure, prefix: a)
                        .coordinateSpace(name: "phone")
                )
                try Self.write(view, scale: phone.scale, name: "\(phone.name)_fruits_\(scene.rawValue)_cur_vs_a.png")
                for (k, v) in measure.values {
                    let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                    all[parts[0], default: [:]][parts[1]] = v
                }
                // 派生値: 縁側＋庭に使える枠（幅・高さ）、頭打ちの向き、使える幅に対する比、余り、
                // レコメンド枠を A でも残した場合と左右の余白を 0 にした場合の枠の幅。
                for prefix in [cur, a] {
                    guard var m = all[prefix], let pw = m["playfield_w_pt"], let ph = m["playfield_h_pt"],
                          let top = m["avail_top_pt"], let bottom = m["avail_bottom_pt"], let inset = m["side_inset_pt"],
                          let spacing = m["stack_spacing_pt"] else { continue }
                    let availW = Double(phone.width) - inset * 2
                    // 縁側＋庭に使える高さ: 今 = 中身の高さ − 上下の余白 − 札 − レコメンド枠 − バナー − 間隔 3 つ、
                    // A = （ナビバーの下からバナーの帯の上まで。帯に下の余白 8 を含む）− 上の余白 − 1 行の札 − 間隔 1 つ。
                    let slotH: Double
                    if prefix == cur {
                        guard let header = m["header_h_pt"], let rec = m["rec_h_pt"], let banner = m["banner_h_pt"] else { continue }
                        slotH = (bottom - top) - Theme.pad * 2 - header - rec - banner - spacing * 3
                    } else {
                        guard let status = m["status_h_pt"] else { continue }
                        slotH = (bottom - top) - LayoutA.spacing - status - spacing
                    }
                    m["avail_w_pt"] = availW
                    m["slot_h_pt"] = (slotH * 100).rounded() / 100
                    m["limited_by"] = pw < availW - 0.5 ? 1 : 0  // 1 = 高さで頭打ち（横幅が余る）, 0 = 幅で頭打ち（縦が余る）
                    m["width_use_ratio"] = (pw / availW * 1000).rounded() / 1000
                    m["slack_below_pt"] = ((slotH - ph) * 100).rounded() / 100
                    m["playfield_w_if_fullbleed_pt"] = (playfieldSize(availableWidth: Double(phone.width), availableHeight: slotH).width * 100).rounded() / 100
                    if prefix == a, let rec = all[cur]?["rec_h_pt"] {
                        m["calc_playfield_w_if_rec_kept_pt"] =
                            (playfieldSize(availableWidth: availW, availableHeight: slotH - rec - spacing).width * 100).rounded() / 100
                    }
                    all[prefix] = m
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.outDir.appendingPathComponent("measure_fruits.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
