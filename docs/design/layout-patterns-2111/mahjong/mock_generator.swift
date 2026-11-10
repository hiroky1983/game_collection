// #2427 のレイアウト検討モック（麻雀ソリティア・今 vs A）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/GameMahjongSolitaireTests/` にコピーし、
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2427
// で `<出力先>/mock2427/` に PNG 4 枚と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 実物の部品（MahjongTileView・GameStatusBar・GameOverflowBar・CardTableSurface・GameControlArea）をそのまま使い、
// ナビバー・ステータスバー・バナーだけ見た目を写して描いている。終わったらコピーは消す（コミットしない）。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreTestSupport
import MahjongTiles
@testable import GameMahjongSolitaire

private typealias Metrics = MahjongSolitaireBoardMetrics

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

private struct BoardCanvas: View {
    let model: MahjongSolitaireModel
    let tileWidth: CGFloat

    var body: some View {
        let canvas = Metrics.canvasSize(tileWidth: tileWidth, layout: model.layout)
        let extent = Metrics.extent(layout: model.layout)
        ZStack(alignment: .topLeading) {
            ForEach(model.faces.indices, id: \.self) { index in
                if let face = model.faces[index] {
                    let f = Metrics.tileFrame(index: index, tileWidth: tileWidth, layout: model.layout, extent: extent)
                    MahjongTileView(
                        face: face, width: f.width, height: f.height,
                        isBlocked: !model.isFreeByIndex[index],
                        isSelected: model.selectedIndex == index,
                        isHinted: false
                    )
                    .offset(x: f.minX, y: f.minY)
                }
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }
}

/// 盤（卓の内側）。全体表示なら収まる牌幅、拡大なら 44pt の牌で中央を見せる（ScrollView は ImageRenderer で白紙になるので clipped で代替）。
private struct Board: View {
    let model: MahjongSolitaireModel
    let zoomed: Bool
    let measure: Measure
    let prefix: String

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let tile = zoomed
                ? Metrics.comfortableTileWidth(in: size, layout: model.layout)
                : Metrics.fittingTileWidth(in: size, layout: model.layout)
            let canvas = Metrics.canvasSize(tileWidth: tile, layout: model.layout)
            let frame = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).inner_w_pt", size.width)
                measure.set("\(prefix).inner_h_pt", size.height)
                measure.set("\(prefix).inner_top_pt", frame.minY)
                measure.set("\(prefix).tile_w_pt", tile)
                measure.set("\(prefix).tile_h_pt", tile * Metrics.tileAspect)
                measure.set("\(prefix).canvas_w_pt", canvas.width)
                measure.set("\(prefix).canvas_h_pt", canvas.height)
                let visW = min(size.width, canvas.width), visH = min(size.height, canvas.height)
                measure.set("\(prefix).visible_ratio", (visW * visH) / (canvas.width * canvas.height))
            }()
            BoardCanvas(model: model, tileWidth: tile)
                .frame(width: size.width, height: size.height, alignment: .center)
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
        // 表示名は「戻る」と右のアイコン群のあいだの中央（iOS の principal の置き方）。
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
private func controlActions(model: MahjongSolitaireModel) -> [GameActionItem] {
    [
        GameActionItem(id: "undo", title: "戻す", systemImage: "arrow.uturn.backward", role: .undo,
                       badge: .count(model.undosRemaining), isEnabled: model.canUndo) {},
        GameActionItem(id: "hint", title: "ヒント", systemImage: "lightbulb.fill", role: .hint, badge: .ad()) {},
        GameActionItem(id: "shuffle", title: "並べ替え", systemImage: "shuffle", role: .primary, badge: .ad()) {},
    ]
}

/// 操作の段 ＋「⋯」。`GameOverflowBar` の Menu は macOS で見た目が変わるので「⋯」だけ自前で描く（寸法は同じ）。
private struct ControlRow: View {
    let model: MahjongSolitaireModel
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

private struct StatusContent: View {
    let model: MahjongSolitaireModel
    let size: CGFloat
    var body: some View {
        Label("\(model.remainingCount)", systemImage: "square.stack.3d.up.fill")
            .scaledFont(size, weight: .bold, design: .monospaced)
            .foregroundStyle(Theme.coralText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// 取り切った後の 1 段（`MahjongSolitaireView.resultControls` の写し。高さのひな形に使う）。
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
    let model: MahjongSolitaireModel
    let services: GameServices
    let zoomed: Bool
    let measure: Measure
    let prefix: String

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone, onFelt: false)
                NavHeader(title: "麻雀ソリティア", onFelt: false)
                VStack(spacing: 8) {
                    GameStatusBar {
                        StatusContent(model: model, size: 16)
                    } trailing: {
                        GameClockLabel("00:42")
                    }
                    Board(model: model, zoomed: zoomed, measure: measure, prefix: prefix)
                        .cardTable()
                        .background(GeometryReader { geo in
                            let f = geo.frame(in: .named("phone"))
                            let _ = {
                                measure.set("\(prefix).table_w_pt", f.width)
                                measure.set("\(prefix).table_h_pt", f.height)
                                measure.set("\(prefix).table_top_pt", f.minY)
                            }()
                            Color.clear
                        })
                        .padding(.horizontal, -(Theme.pad - CardStackLayout.boardSideInset))
                        .layoutPriority(1)
                    GameControlArea(isFinished: false, services: services) {
                        ResultControls()
                    } playing: {
                        ControlRow(model: model)
                    }
                    Spacer(minLength: 0)
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

private struct FullScreenA: View {
    let phone: Phone
    let model: MahjongSolitaireModel
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
                // 画面最下部のバナー（会長の方針: A のバナーは下）。地の色の帯に置く。
                VStack(spacing: 0) {
                    BannerPlaceholder().padding(.horizontal, Theme.pad).padding(.top, 8)
                    Color.clear.frame(height: phone.safeBottom)
                }
            }
            VStack(spacing: 0) {
                StatusStrip(phone: phone, onFelt: true)
                NavHeader(title: "麻雀ソリティア", onFelt: true)
                VStack(spacing: 8) {
                    // 手数・時計は 1 行の札にまとめる（今の 44pt の帯より低い）。
                    HStack(spacing: 8) {
                        StatusContent(model: model, size: 15)
                        Spacer(minLength: 8)
                        GameClockLabel("00:42")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .popCard(corner: 10)
                    .background(GeometryReader { geo in
                        let _ = measure.set("\(prefix).status_h_pt", geo.size.height)
                        Color.clear
                    })
                    .padding(.horizontal, Theme.pad)
                    Board(model: model, zoomed: zoomed, measure: measure, prefix: prefix)
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

@Suite("#2427 レイアウト検討モック（一時）")
struct LayoutMock2427Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2427", isDirectory: true)
    }

    @MainActor
    private static func makeModel() -> (MahjongSolitaireModel, GameServices) {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = MahjongSolitaireModel(services: services, seed: 2427, layout: .turtle)
        // 1 組取ってから（「戻す」が押せる状態）、次の牌を 1 枚選んだ局面にする。
        let free = model.faces.indices.filter { model.isFreeByIndex[$0] && model.faces[$0] != nil }
        outer: for a in free {
            for b in free where b > a {
                if let fa = model.faces[a], let fb = model.faces[b], fa.matches(fb) {
                    model.tap(a); model.tap(b); break outer
                }
            }
        }
        if let pick = model.faces.indices.first(where: { model.isFreeByIndex[$0] && model.faces[$0] != nil && $0 > 20 }) {
            model.tap(pick)
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
                let cur = "\(phone.name)_\(mode)_cur", a = "\(phone.name)_\(mode)_a"
                let view = SideBySide(
                    leftCaption: "今（\(zoomed ? "拡大" : "全体表示")）",
                    rightCaption: "A 全画面（\(zoomed ? "拡大" : "全体表示")）",
                    left: CurrentScreen(phone: phone, model: model, services: services, zoomed: zoomed, measure: measure, prefix: cur)
                        .coordinateSpace(name: "phone"),
                    right: FullScreenA(phone: phone, model: model, zoomed: zoomed, measure: measure, prefix: a)
                        .coordinateSpace(name: "phone")
                )
                try Self.write(view, scale: phone.scale, name: "\(phone.name)_mahjongsolitaire_\(mode)_cur_vs_a.png")
                for (k, v) in measure.values {
                    let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                    all[parts[0], default: [:]][parts[1]] = v
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.outDir.appendingPathComponent("measure_mahjongsolitaire.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
