// #2440 のレイアウト検討モック（15パズル・今 vs C vs A）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/GameFifteenTests/` にコピーし、
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2440
// で `<出力先>/mock2440/` に PNG 6 枚と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 実物の部品（`FifteenTile`・`GameOverflowBar`・`GameActionItem`・`RecommendationArea`・popCard・scaledFont）をそのまま使い、
// 盤の並べ方は `FifteenView.boardView`（private）の写し、ナビバー・ステータスバー・バナーは見た目を写して描いている。
// #2427（麻雀ソリティア）以降の兄弟 Issue の生成器と同じ型（C の仮の枠はマインスイーパー #2438 と同じ）。
// 「今」は release/v1.1.13（#2322 の正位置のチェック印反映後）の `FifteenView.body` の写し。終わったらコピーは消す（コミットしない）。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreTestSupport
@testable import GameFifteen

private struct Phone {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let scale: CGFloat
    /// iOS 26 のナビバーの高さ。iPhone 17 は 54pt（実スクショ ip17_spiderzoom_v2cur.png の実測）、
    /// iPhone SE は 44pt（#2435 のブロック崩しで `BlocksLayoutTests.devices` の実機プローブに合わせた値。非ノッチ端末の標準）。
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

/// C の「大きいバナー」の仮の枠。大きさは会長決裁待ち（#2111「C のバナーの大きさ」）なので、AdMob の 2 つの定型を描く。
private enum BannerKind {
    /// 今のアダプティブバナー（枠 50pt）。
    case standard
    /// ラージバナー 320×100（枠 100pt）。
    case large
    /// ミディアムレクタングル 300×250（枠 250pt。柵越えおじさんの記録ページで既に使っている寸法・`MediumRectangleSlot`）。
    case mrec

    var slotHeight: CGFloat {
        switch self {
        case .standard: return 50   // BannerSlot.height（View の static は MainActor 隔離なのでここでは値を書く）
        case .large: return 100
        case .mrec: return 250
        }
    }
    var adSize: CGSize? {
        switch self {
        case .standard: return nil
        case .large: return CGSize(width: 320, height: 100)
        case .mrec: return CGSize(width: 300, height: 250)
        }
    }
    var label: String {
        switch self {
        case .standard: return "バナー広告（50pt・そのまま残す）"
        case .large: return "大きいバナー（仮・ラージバナー 320×100）"
        case .mrec: return "大きいバナー（仮・MREC 300×250）"
        }
    }
    var suffix: String {
        switch self {
        case .standard: return "cur"
        case .large: return "c100"
        case .mrec: return "c250"
        }
    }
}

// MARK: - 今の画面の部品（FifteenView の写し）

/// 手数のカード（`FifteenView.header` の写し）。
private struct MovesHeader: View {
    let model: FifteenModel
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("手数")
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.moves)")
                    .scaledFont(30, weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).status_h_pt", geo.size.height)
            Color.clear
        })
    }
}

/// 盤（`FifteenView.boardView` の写し）。タイルは実物の `FifteenTile`。正方形・角丸・影。呼び出し側で `.layoutPriority(1)` を付ける。
private struct Board: View {
    let model: FifteenModel
    let measure: Measure
    let prefix: String
    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let n = FifteenLogic.size
            let side = (geo.size.width - spacing * CGFloat(n + 1)) / CGFloat(n)
            let f = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).board_w_pt", geo.size.width)
                measure.set("\(prefix).board_h_pt", geo.size.height)
                measure.set("\(prefix).board_top_pt", f.minY)
                measure.set("\(prefix).board_left_pt", f.minX)
                measure.set("\(prefix).tile_pt", side)
                measure.set("\(prefix).tile_gap_pt", spacing)
            }()
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.fillMuted)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                ForEach(1..<FifteenLogic.cellCount, id: \.self) { value in
                    if let index = model.tiles.firstIndex(of: value) {
                        FifteenTile(value: value, side: side, isHome: index == value - 1, isHint: index == model.hintIndex)
                            .offset(
                                x: spacing + CGFloat(index % n) * (side + spacing),
                                y: spacing + CGFloat(index / n) * (side + spacing)
                            )
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

@MainActor
private func hintAction(model: FifteenModel) -> GameActionItem {
    GameActionItem(
        id: "hint", title: "ヒント", systemImage: "lightbulb.fill", role: .hint,
        badge: .hint(totalRemaining: model.hintsRemaining, needsAd: model.needsAdForHint),
        isEnabled: model.canUseHint
    ) {}
}

/// 盤の下の操作の段（`FifteenView.hintBar` の写し）。ヒントだけで「⋯」は無い（menuItems が空）。実物の `GameOverflowBar`（上下 4pt）。
private struct HintRow: View {
    let model: FifteenModel
    let measure: Measure
    let prefix: String
    var body: some View {
        GameOverflowBar(actions: [hintAction(model: model)], verticalPadding: 4)
            .background(GeometryReader { geo in
                let f = geo.frame(in: .named("phone"))
                let _ = {
                    measure.set("\(prefix).control_h_pt", geo.size.height)
                    measure.set("\(prefix).control_bottom_pt", f.maxY)
                }()
                Color.clear
            })
    }
}

/// レコメンド枠の予約（実物の `RecommendationArea`。決着前は不可視のひな形だけ）。
private struct RecommendArea: View {
    let services: GameServices
    let measure: Measure
    let prefix: String
    var body: some View {
        RecommendationArea(services: services, isFinished: false)
            .background(GeometryReader { geo in
                let _ = measure.set("\(prefix).recommend_h_pt", geo.size.height)
                Color.clear
            })
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

/// iOS 26 の「戻る ＋ ゲーム名 ＋ 右のアイコン群（？・＋）」。＋の絵柄は v1.1.13 から全種類 `plus.circle.fill`（#2370）、色は `Theme.coralText`（#2377）。
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

/// バナーの仮の枠。C の大きいバナーは、枠（幅いっぱい・薄い灰）の中に広告そのものの寸法（濃い灰・中央）を描いて大きさが分かるようにする。
private struct BannerPlaceholder: View {
    let kind: BannerKind
    let measure: Measure
    let prefix: String
    var body: some View {
        ZStack {
            Color(white: 0.86)
            if let ad = kind.adSize {
                Color(white: 0.76).frame(width: ad.width, height: ad.height)
            }
            Text(verbatim: kind.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(white: 0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: kind.slotHeight)
        .background(GeometryReader { geo in
            let f = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).banner_h_pt", geo.size.height)
                measure.set("\(prefix).banner_top_pt", f.minY)
            }()
            Color.clear
        })
    }
}

/// レコメンド枠とバナーのあいだの余り。今は `Spacer()`（最小 = システム既定の 8pt）、A は `Spacer(minLength: 0)`。
private struct Slack: View {
    let minLength: CGFloat?
    let measure: Measure
    let prefix: String
    var body: some View {
        Spacer(minLength: minLength)
            .background(GeometryReader { geo in
                let _ = measure.set("\(prefix).slack_pt", geo.size.height)
                Color.clear
            })
    }
}

// MARK: - 今の画面（FifteenView.body の写し）／C（バナーだけ大きい）

private struct CurrentScreen: View {
    let phone: Phone
    let model: FifteenModel
    let services: GameServices
    let banner: BannerKind
    let measure: Measure
    let prefix: String

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader(phone: phone, title: "15パズル")
                // 縦の間隔は 14（`FifteenView.body` の VStack(spacing: 14)）。手数 → 盤 → ヒントの段 → レコメンド枠の予約 → 余り → 広告。
                VStack(spacing: 14) {
                    MovesHeader(model: model, measure: measure, prefix: prefix)
                    Board(model: model, measure: measure, prefix: prefix)
                        .layoutPriority(1)
                    HintRow(model: model, measure: measure, prefix: prefix)
                    // HowToPlayHint（初回だけ 1 行のミニガイド）は 2 回目以降は出ないので描かない。
                    RecommendArea(services: services, measure: measure, prefix: prefix)
                    Slack(minLength: nil, measure: measure, prefix: prefix)
                    BannerPlaceholder(kind: banner, measure: measure, prefix: prefix)
                }
                .padding(Theme.pad)
                Color.clear.frame(height: phone.safeBottom)
            }
        }
        .frame(width: phone.width, height: phone.height)
    }
}

// MARK: - A（全画面）

/// 手数を 1 行の札にまとめる（会長の方針: 手数・点数などの表示は 1 行の札に）。
private struct StatusPill: View {
    let model: FifteenModel
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack(spacing: 8) {
            Text("手数")
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.inkSub)
            Text("\(model.moves)")
                .scaledFont(17, weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
        }
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
    let model: FifteenModel
    /// 画面最下部のバナー。A は 50pt のまま。「A の詰め方に大きいバナーを足したら盤はどうなるか」の計算のために .large でも測る（画像は作らない）。
    var banner: BannerKind = .standard
    let measure: Measure
    let prefix: String

    /// 左右の余白。今の 16pt から 8pt に詰める（兄弟 Issue の A と同じ）。盤は正方形なので、増えた幅 16pt がそのまま盤の一辺に乗る。
    static let sideInset: CGFloat = 8

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader(phone: phone, title: "15パズル")
                // 縦の間隔は兄弟の A と同じ 8（今の 14 より詰める）。
                VStack(spacing: 8) {
                    StatusPill(model: model, measure: measure, prefix: prefix)
                    Board(model: model, measure: measure, prefix: prefix)
                        .layoutPriority(1)
                    // 操作の段は盤のすぐ下。レコメンドカードの置き場所（今は 56pt の予約）は共通化のときに決める（兄弟のモックと同じ）。
                    HintRow(model: model, measure: measure, prefix: prefix)
                    Slack(minLength: 0, measure: measure, prefix: prefix)
                }
                .padding(.horizontal, Self.sideInset)
                .padding(.top, 8)
                .padding(.bottom, 8)
                // 画面最下部のバナー（会長の方針: A のバナーは下）。
                BannerPlaceholder(kind: banner, measure: measure, prefix: prefix).padding(.horizontal, Theme.pad)
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

private struct SceneInfo {
    let seed: UInt64
    let moves: Int
    let homeCount: Int
    let hintsRemaining: Int
}

@MainActor
private func homeCount(_ tiles: [Int]) -> Int {
    tiles.enumerated().filter { $0.element != 0 && $0.element == $0.offset + 1 }.count
}

/// 局面。実物の `FifteenModel(services:seed:)` で種から配り、`FifteenHintSolver` の示す升を実物の `tap` で動かして
/// 「途中の局」を作る（正位置のタイルが 6〜7 枚になったところで止める。ソルバーは列や行の順には揃えないので、揃った列があるとは限らない）。
/// 手数が 30〜70 に入る最初の種を使う（JSON の `seed` は `FifteenModel(seed:)` に渡した値そのもの）。
@MainActor
private func makeModel() -> (FifteenModel, GameServices, SceneInfo) {
    for n in UInt64(1)...UInt64(200) {
        let seed = n &* 2440
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let model = FifteenModel(services: services, seed: seed)
        var steps = 0
        while !model.isSolved, steps < 400 {
            if homeCount(model.tiles) >= 6 { break }
            guard let index = FifteenHintSolver.nextIndex(model.tiles) else { break }
            model.tap(at: index)
            steps += 1
        }
        let homes = homeCount(model.tiles)
        guard !model.isSolved, (6...7).contains(homes), (30...70).contains(model.moves) else { continue }
        return (model, services, SceneInfo(seed: seed, moves: model.moves, homeCount: homes, hintsRemaining: model.hintsRemaining))
    }
    fatalError("狙いの局面になる種が見つからない")
}

@Suite("#2440 レイアウト検討モック（一時）")
struct LayoutMock2440Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2440", isDirectory: true)
    }

    /// 描く（寸法を書き留めるのが目的なので `save` が false なら PNG は書かない）。
    @MainActor
    private static func render(_ view: some View, scale: CGFloat, name: String, save: Bool) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        guard save else { return }
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent(name)
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        print("wrote \(url.path) \(image.width)x\(image.height)")
    }

    @Test("今 vs C vs A を描いて寸法を書き出す")
    @MainActor
    func render() throws {
        NSApp?.appearance = NSAppearance(named: .aqua)
        var all: [String: [String: Double]] = [:]
        let (model, services, info) = makeModel()
        print("scene: seed \(info.seed) moves \(info.moves) home \(info.homeCount) hints \(info.hintsRemaining) tiles \(model.tiles)")
        all["scene_mid"] = [
            "seed": Double(info.seed), "moves": Double(info.moves), "home_count": Double(info.homeCount),
            "hints_remaining": Double(info.hintsRemaining),
        ]
        for phone in phones {
            let measure = Measure()
            let base = "\(phone.name)_mid"
            let cur = "\(base)_cur"
            // 今 vs C（ラージバナー 100pt）・今 vs C（MREC 250pt）・今 vs A。
            for kind in [BannerKind.large, .mrec] {
                let view = SideBySide(
                    leftCaption: "今（v1.1.13）",
                    rightCaption: "C 盤＋大きいバナー（仮 \(Int(kind.slotHeight))pt）",
                    left: CurrentScreen(phone: phone, model: model, services: services, banner: .standard, measure: measure, prefix: cur)
                        .coordinateSpace(name: "phone"),
                    right: CurrentScreen(phone: phone, model: model, services: services, banner: kind, measure: measure, prefix: "\(base)_\(kind.suffix)")
                        .coordinateSpace(name: "phone")
                )
                let name = kind == .large ? "\(phone.name)_fifteen_mid_cur_vs_c.png" : "\(phone.name)_fifteen_mid_cur_vs_c250.png"
                try Self.render(view, scale: phone.scale, name: name, save: true)
            }
            let viewA = SideBySide(
                leftCaption: "今（v1.1.13）",
                rightCaption: "A 全画面",
                left: CurrentScreen(phone: phone, model: model, services: services, banner: .standard, measure: measure, prefix: cur)
                    .coordinateSpace(name: "phone"),
                right: FullScreenA(phone: phone, model: model, measure: measure, prefix: "\(base)_a")
                    .coordinateSpace(name: "phone")
            )
            try Self.render(viewA, scale: phone.scale, name: "\(phone.name)_fifteen_mid_cur_vs_a.png", save: true)
            // 計算用: A の詰め方（1 行の札・左右 8pt・レコメンド枠の予約なし）のままバナーだけ 100pt / 250pt にしたら盤はどうなるか（画像は作らない）。
            try Self.render(
                FullScreenA(phone: phone, model: model, banner: .large, measure: measure, prefix: "\(base)_a100").coordinateSpace(name: "phone"),
                scale: 1, name: "", save: false)
            try Self.render(
                FullScreenA(phone: phone, model: model, banner: .mrec, measure: measure, prefix: "\(base)_a250").coordinateSpace(name: "phone"),
                scale: 1, name: "", save: false)

            for (k, v) in measure.values {
                let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                all[parts[0], default: [:]][parts[1]] = v
            }
            // 派生値: 使える幅・頭打ちの向き・盤の下から広告の上までの距離。
            for (prefix, sideInset) in [(cur, Theme.pad), ("\(base)_c100", Theme.pad), ("\(base)_c250", Theme.pad),
                                        ("\(base)_a", FullScreenA.sideInset), ("\(base)_a100", FullScreenA.sideInset), ("\(base)_a250", FullScreenA.sideInset)] {
                guard var m = all[prefix], let bw = m["board_w_pt"] else { continue }
                let availW = Double(phone.width - sideInset * 2)
                m["avail_w_pt"] = availW
                m["limited_by"] = bw < availW - 0.5 ? 1 : 0  // 1 = 高さで頭打ち（横幅が余る）, 0 = 幅で頭打ち
                m["width_use_ratio"] = (bw / availW * 1000).rounded() / 1000
                if let bt = m["board_top_pt"], let bh = m["board_h_pt"], let at = m["banner_top_pt"] {
                    m["board_bottom_to_banner_pt"] = ((at - bt - bh) * 100).rounded() / 100
                }
                all[prefix] = m
            }
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        try data.write(to: Self.outDir.appendingPathComponent("measure_fifteen.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
