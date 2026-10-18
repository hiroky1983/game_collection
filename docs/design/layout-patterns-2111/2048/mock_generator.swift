// #2439 のレイアウト検討モック（2048・今 vs C vs A）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/Game2048Tests/` にコピーし、
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2439
// で `<出力先>/mock2439/` に PNG 10 枚と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 実物の部品（`TileView`・`GameOverflowBar`・`RecommendationArea`・`popCard`・`themeBody` / `themeCaption`）をそのまま使い、
// 盤・スコアの札は `Game2048View.boardView` / `header` の写し（private なので同じ寸法・色で組み直し）、
// ナビバー・ステータスバー・バナーは見た目を写して描いている。#2427（麻雀ソリティア）・#2438（マインスイーパー）以降の兄弟 Issue の生成器と同じ型。
// 「今」は `Game2048View.body`（main と release/v1.1.13 で同じ。差は遊び方の図の 2 行だけ）。終わったらコピーは消す（コミットしない）。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreTestSupport
@testable import Game2048

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

// MARK: - 今の画面の部品（Game2048View の写し）

/// 「戻す」の段を盤から追加で離す量（`Game2048View.undoGapExtra`・#2253）。
private let undoGapExtra: CGFloat = 12
/// 盤のマスの間隔（`Game2048View.boardView` の `spacing`）。
private let tileSpacing: CGFloat = 8

/// スコアの札（`Game2048View.header` の写し。popCard・縦の余白 10・横 18）。
private struct ScoreHeader: View {
    let model: Game2048Model
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("スコア")
                    .themeCaption(12, weight: .bold, maxScale: 1.5)
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.score)")
                    .themeBody(30, weight: .heavy, maxScale: 1.5).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).header_h_pt", geo.size.height)
            Color.clear
        })
    }
}

/// 盤（`Game2048View.boardView` の写し）。正方形（`aspectRatio(1, .fit)`）・角丸 `Theme.corner`・影。
/// タイルは実物の `TileView`（@testable）を `model.tiles` の座標に置く。呼び出し側で `.layoutPriority(1)` を付ける。
private struct Board: View {
    let model: Game2048Model
    let measure: Measure
    let prefix: String
    var body: some View {
        GeometryReader { geo in
            let n = Game2048Logic.size
            let tileSize = max(0, (geo.size.width - tileSpacing * CGFloat(n + 1)) / CGFloat(n))
            let f = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).board_w_pt", geo.size.width)
                measure.set("\(prefix).board_h_pt", geo.size.height)
                measure.set("\(prefix).board_top_pt", f.minY)
                measure.set("\(prefix).board_left_pt", f.minX)
                measure.set("\(prefix).tile_pt", tileSize)
            }()
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(hex: 0xE7C9A8))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                VStack(spacing: tileSpacing) {
                    ForEach(0..<n, id: \.self) { _ in
                        HStack(spacing: tileSpacing) {
                            ForEach(0..<n, id: \.self) { _ in
                                TileView(value: 0, size: tileSize)
                            }
                        }
                    }
                }
                .padding(tileSpacing)
                ForEach(model.tiles, id: \.id) { tile in
                    TileView(value: tile.value, size: tileSize)
                        .offset(x: tileSpacing + CGFloat(tile.col) * (tileSize + tileSpacing),
                                y: tileSpacing + CGFloat(tile.row) * (tileSize + tileSpacing))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

@MainActor
private func undoAction(model: Game2048Model) -> GameActionItem {
    GameActionItem(
        id: "undo", title: "戻す", systemImage: "arrow.uturn.backward", role: .undo,
        badge: model.undosRemaining > 0 ? .count(model.undosRemaining) : .ad(gain: RewardedUndoBudget.refill),
        isEnabled: model.canUndo
    ) {}
}

/// 操作の段（「戻す」だけ。2048 は「⋯」を持たない・`Game2048View.gameControls` の写し）。実物の `GameOverflowBar`（上下の余白 8・行 44）。
private struct ControlRow: View {
    let model: Game2048Model
    let measure: Measure
    let prefix: String
    var body: some View {
        GameOverflowBar(actions: [undoAction(model: model)])
            .lineLimit(1)
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

/// レコメンドカードの枠（実物の `RecommendationArea`。ひな形の高さを常に確保する・#148）。
private struct RecommendArea: View {
    let services: GameServices
    let measure: Measure
    let prefix: String
    var body: some View {
        RecommendationArea(services: services, isFinished: false)
            .background(GeometryReader { geo in
                let f = geo.frame(in: .named("phone"))
                let _ = {
                    measure.set("\(prefix).recommend_h_pt", geo.size.height)
                    measure.set("\(prefix).recommend_bottom_pt", f.maxY)
                }()
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

/// レコメンド枠とバナーのあいだの余り（今は `Spacer()`。A は `Spacer(minLength: 0)`）。
private struct Slack: View {
    let measure: Measure
    let prefix: String
    var minLength: CGFloat? = nil
    var body: some View {
        Spacer(minLength: minLength)
            .background(GeometryReader { geo in
                let _ = measure.set("\(prefix).slack_pt", geo.size.height)
                Color.clear
            })
    }
}

// MARK: - 今の画面（Game2048View.body の写し）／C（バナーだけ大きい）

private struct CurrentScreen: View {
    let phone: Phone
    let model: Game2048Model
    let services: GameServices
    let banner: BannerKind
    let measure: Measure
    let prefix: String

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader(phone: phone, title: "2048")
                // 縦の余白は 14（#148）。スコア → 盤（下に 12 のスワイプ余白・#2253）→ 「戻す」の段（下側の余白を 12 詰める）
                // → レコメンド枠（常に高さを確保・#148）→ 余り（`Spacer()`）→ 広告。
                VStack(spacing: 14) {
                    ScoreHeader(model: model, measure: measure, prefix: prefix)
                    Board(model: model, measure: measure, prefix: prefix)
                        .padding(.bottom, undoGapExtra)
                        .layoutPriority(1)
                    ControlRow(model: model, measure: measure, prefix: prefix)
                        .padding(.bottom, -undoGapExtra)
                    // HowToPlayHint（初回だけ 1 行のミニガイド）は 2 回目以降は出ないので描かない。
                    RecommendArea(services: services, measure: measure, prefix: prefix)
                    Slack(measure: measure, prefix: prefix)
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

/// スコアを 1 行の札にまとめる（会長の方針: 手数・点数などの表示は 1 行の札に）。文字は 30 → 20pt。
private struct ScorePill: View {
    let model: Game2048Model
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack(spacing: 8) {
            Text("スコア")
                .themeCaption(12, weight: .bold, maxScale: 1.5)
                .foregroundStyle(Theme.inkSub)
            Text("\(model.score)")
                .themeBody(20, weight: .heavy, maxScale: 1.5).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .popCard(corner: 10)
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).header_h_pt", geo.size.height)
            Color.clear
        })
    }
}

private struct FullScreenA: View {
    let phone: Phone
    let model: Game2048Model
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
                NavHeader(phone: phone, title: "2048")
                VStack(spacing: 8) {
                    ScorePill(model: model, measure: measure, prefix: prefix)
                    // 盤の直下のスワイプ余白（#2253・12pt）は A でも残す（盤の下端ぎりぎりのスワイプを「戻す」が拾わないための契約）。
                    Board(model: model, measure: measure, prefix: prefix)
                        .padding(.bottom, undoGapExtra)
                        .layoutPriority(1)
                    // 操作の段は盤のすぐ下。レコメンド枠の予約（`RecommendationArea`・56pt）は外してあり、置き場所は共通化のときに決める（兄弟のモックと同じ）。
                    ControlRow(model: model, measure: measure, prefix: prefix)
                    Slack(measure: measure, prefix: prefix, minLength: 0)
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

private struct SceneSpec {
    let name: String
    let board: [[Int]]
    let score: Int
    /// 「戻す」の残り回数（0 なら札は「広告を見て +3」になる）。
    let undosRemaining: Int
    let caption: String
}

/// 2048 は盤そのものを中断データに持つ（乱数の種は無い）ので、局面は盤を直接書く。
/// 「戻す」を押せる状態（履歴 1 段）にするため、中断データ（`Game2048Snapshot`）に履歴を入れて `init(services:)` で復元する
/// （`init(board:)` だと履歴が空で「戻す」が押せない見た目になる）。履歴の中身は描画には出ない。
private let scenes = [
    SceneSpec(
        name: "mid",
        board: [
            [2, 4, 0, 0],
            [8, 16, 2, 0],
            [32, 64, 8, 2],
            [1024, 256, 128, 4],
        ],
        score: 12_312, undosRemaining: 2,
        caption: "局の途中（最大 1024・空き 3・戻す あと 2 回）"
    ),
    SceneSpec(
        name: "late",
        board: [
            [4, 2, 8, 4],
            [16, 32, 64, 8],
            [128, 512, 16, 2],
            [2048, 1024, 256, 0],
        ],
        score: 36_940, undosRemaining: 0,
        caption: "終盤（2048 到達後に続行・空き 1・戻す は広告で補充）"
    ),
]

@MainActor
private func makeModel(_ scene: SceneSpec) -> (Game2048Model, GameServices) {
    let store = MemorySnapshotStore()
    let hasWon = Game2048Logic.hasWinningTile(scene.board)
    // 履歴の 1 段（戻した先）。描画には出ないので、同じ盤を少し前の得点で入れておくだけ。
    let previous = Game2048Step(board: scene.board, score: max(0, scene.score - 4), hasWon: hasWon)
    try! store.save(
        Game2048Snapshot(board: scene.board, score: scene.score, continueUsed: false, hasWon: hasWon,
                         showWinPrompt: false, history: [previous], undosRemaining: scene.undosRemaining),
        for: "2048")
    let services = GameServices(snapshots: store, ads: NoopAdService())
    let model = Game2048Model(services: services)
    return (model, services)
}

@Suite("#2439 レイアウト検討モック（一時）")
struct LayoutMock2439Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2439", isDirectory: true)
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
        for scene in scenes {
            let (model, services) = makeModel(scene)
            #expect(model.board == scene.board)
            #expect(model.score == scene.score)
            #expect(model.canUndo, "履歴 1 段で「戻す」が押せる見た目にする")
            #expect(!model.gameOver && !model.showWinPrompt, "幕の無い局面で盤を測る")
            print("\(scene.name): score \(model.score) tiles \(model.tiles.count) undos \(model.undosRemaining) canUndo \(model.canUndo) hasWon \(model.hasWon)")
            all["scene_\(scene.name)"] = [
                "score": Double(scene.score), "tiles": Double(model.tiles.count),
                "empty": Double(Game2048Logic.emptyCells(scene.board).count),
                "max_tile": Double(scene.board.flatMap { $0 }.max() ?? 0),
                "undos_remaining": Double(scene.undosRemaining),
            ]
            for phone in phones {
                let measure = Measure()
                let base = "\(phone.name)_\(scene.name)"
                let cur = "\(base)_cur"
                let fileBase = "\(phone.name)_2048_\(scene.name)"
                // 今 vs C（ラージバナー 100pt）・今 vs C（MREC 250pt・画像は mid だけ）・今 vs A。
                for kind in [BannerKind.large, .mrec] {
                    let view = SideBySide(
                        leftCaption: "今（v1.1.13）",
                        rightCaption: "C 盤＋大きいバナー（仮 \(Int(kind.slotHeight))pt）",
                        left: CurrentScreen(phone: phone, model: model, services: services, banner: .standard, measure: measure, prefix: cur)
                            .coordinateSpace(name: "phone"),
                        right: CurrentScreen(phone: phone, model: model, services: services, banner: kind, measure: measure, prefix: "\(base)_\(kind.suffix)")
                            .coordinateSpace(name: "phone")
                    )
                    let name = kind == .large ? "\(fileBase)_cur_vs_c.png" : "\(fileBase)_cur_vs_c250.png"
                    try Self.render(view, scale: phone.scale, name: name, save: kind == .large || scene.name == "mid")
                }
                let viewA = SideBySide(
                    leftCaption: "今（v1.1.13）",
                    rightCaption: "A 全画面",
                    left: CurrentScreen(phone: phone, model: model, services: services, banner: .standard, measure: measure, prefix: cur)
                        .coordinateSpace(name: "phone"),
                    right: FullScreenA(phone: phone, model: model, measure: measure, prefix: "\(base)_a")
                        .coordinateSpace(name: "phone")
                )
                try Self.render(viewA, scale: phone.scale, name: "\(fileBase)_cur_vs_a.png", save: true)
                // 計算用: A の詰め方（1 行の札・左右 8pt・レコメンド枠の予約なし）のままバナーだけ 100pt にしたら盤はどうなるか（画像は作らない）。
                try Self.render(
                    FullScreenA(phone: phone, model: model, banner: .large, measure: measure, prefix: "\(base)_a100").coordinateSpace(name: "phone"),
                    scale: 1, name: "", save: false)

                for (k, v) in measure.values {
                    let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                    all[parts[0], default: [:]][parts[1]] = v
                }
                // 派生値: 使える幅・頭打ちの向き・盤の下から広告の上までの距離・今の組み方で盤を縮めずに入るバナーの枠。
                for (prefix, sideInset) in [(cur, Theme.pad), ("\(base)_c100", Theme.pad), ("\(base)_c250", Theme.pad),
                                            ("\(base)_a", FullScreenA.sideInset), ("\(base)_a100", FullScreenA.sideInset)] {
                    guard var m = all[prefix], let bw = m["board_w_pt"] else { continue }
                    let availW = Double(phone.width - sideInset * 2)
                    m["avail_w_pt"] = availW
                    m["limited_by"] = bw < availW - 0.5 ? 1 : 0  // 1 = 高さで頭打ち（横幅が余る）, 0 = 幅で頭打ち
                    m["width_use_ratio"] = (bw / availW * 1000).rounded() / 1000
                    if let bt = m["board_top_pt"], let bh = m["board_h_pt"], let at = m["banner_top_pt"] {
                        m["board_bottom_to_banner_pt"] = ((at - bt - bh) * 100).rounded() / 100
                    }
                    if let slack = m["slack_pt"], let banner = m["banner_h_pt"] {
                        // 余りをバナーに回したときの枠の高さ（盤もスコアの札もこの枠までなら 1pt も縮まない）。
                        // 今の組み方の余りは `Spacer()` で、その最小 8pt はバナーに回せないので差し引く（A は `Spacer(minLength: 0)` なので 0）。
                        let spacerMin: Double = prefix.hasSuffix("_a") || prefix.hasSuffix("_a100") ? 0 : 8
                        m["max_banner_without_shrink_pt"] = ((banner + max(0, slack - spacerMin)) * 100).rounded() / 100
                    }
                    all[prefix] = m
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        try data.write(to: Self.outDir.appendingPathComponent("measure_2048.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
