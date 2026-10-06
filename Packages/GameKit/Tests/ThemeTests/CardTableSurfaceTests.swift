import Testing
import Foundation
import CoreGraphics
import SwiftUI
import Core
import GameKitTestSupport

/// 卓の面（#1501 / #1535）を固定する。
///
/// 麻雀（4 人打ち）と 4 本（ソリティア・スパイダー・フリーセル・麻雀ソリティア）が**同じ 1 つの卓の部品**
/// （`CardTableSurface` / `cardTable`）に乗っていること、卓の色が `CardTableStyle` の 1 か所だけで決まること、
/// フェルトの上に置く空き枠・文字が読めること（コントラスト）を、数値とソースの 2 方向から見る。
@Suite("卓の面")
struct CardTableSurfaceTests {

    // MARK: - 色は 1 か所だけ（#1535）

    @Test("卓の色（フェルト 2 色・木枠の上端）は CardTableStyle の外のソースに書かれていない")
    func tableColorsLiveOnlyInTheStyle() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/CardTable.swift"))
        let style = try #require(SourceScan.declaration(of: "public enum CardTableStyle", in: source))
        // 木枠の中・下の 2 色は麻雀の手牌の牌台（`MahjongWoodTray`。卓ではない別の部品）も使うので、
        // 卓に固有のフェルト 2 色と木枠の上端の色で見る。
        let literals = [CardTableStyle.feltCenter, CardTableStyle.feltEdge, CardTableStyle.rimTop]
            .map { String(format: "0x%06X", $0) }
        for literal in literals {
            #expect(style.contains(literal), "CardTableStyle に \(literal) が無い")
            #expect(SourceScan.matchCount(of: literal, in: source) == 1,
                    "CardTable.swift の CardTableStyle の外に \(literal) がある")
        }
        let modules = try FileManager.default.contentsOfDirectory(
            atPath: SourceScan.packageRoot.appendingPathComponent("Sources").path)
        #expect(modules.contains("GameMahjong") && modules.contains("GameSolitaire"), "走査の空振り")
        for module in modules where module != "Core" {
            guard let other = try? SourceScan.moduleSources(module) else { continue }
            let code = SourceScan.strippingComments(other)
            for literal in literals {
                #expect(!code.contains(literal), "\(module) が卓の色 \(literal) を直書きしている（CardTableStyle を使う）")
            }
        }
    }

    @Test("卓の形（CardTableFrame）は色を持たない（呼び出し側で色を変えられない）")
    func tableFrameHasNoColor() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/CardTable.swift"))
        let frame = try #require(SourceScan.declaration(of: "public struct CardTableFrame", in: source))
        #expect(!frame.contains("Color"), "CardTableFrame に色の設定がある")
        let modifier = try #require(SourceScan.declaration(of: "func cardTable(", in: source))
        #expect(!modifier.contains("Color"), "cardTable が色を受け取っている")
    }

    // MARK: - 形

    @Test("4 本の卓の木枠の太さと内側の影は麻雀（4 人打ち）の左右・下と同じ比")
    func standardFrameMatchesTheMahjongRim() {
        let f = CardTableFrame.standard
        for edge in [f.top, f.leading, f.bottom, f.trailing] {
            #expect(edge == .widthFraction(12 / 393))
        }
        #expect(f.innerShadow == .standard)
        #expect(CardTableFrame.InnerShadow.standard ==
                .init(opacity: 0.45, width: .widthFraction(0.016), blur: .widthFraction(0.01)))
        #expect(f.aspectRatio == nil, "4 本の卓は空いている大きさいっぱい")
        #expect(f.cornerRadius == Theme.corner)
    }

    @Test("木枠の太さは pt でも幅の比でも指定でき、フェルトはその内側")
    func feltRectFollowsTheFrame() {
        let frame = CardTableFrame(top: .points(10), leading: .widthFraction(0.1),
                                   bottom: .points(4), trailing: .widthFraction(0.05))
        let felt = frame.feltRect(in: CGSize(width: 200, height: 300))
        #expect(felt == CGRect(x: 20, y: 10, width: 170, height: 286))
        // 大きさ 0（SwiftUI の最初のレイアウト）でも負の大きさを作らない。
        #expect(frame.feltRect(in: .zero).width == 0)
        #expect(frame.feltRect(in: .zero).height == 0)
    }

    @MainActor
    @Test("cardTable は幅の比で決まる木枠を解いて、中身の大きさ + 木枠 + 余白の卓を作る")
    func cardTableSolvesTheRimFromTheWidth() throws {
        let inner = CGSize(width: 300, height: 200)
        let renderer = ImageRenderer(content: Color.clear.frame(width: inner.width, height: inner.height).cardTable())
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let pad = CardTableStyle.contentInset
        let width = (inner.width + pad * 2) / (1 - 2 * 12 / 393)
        let rim = width * 12 / 393
        #expect(abs(CGFloat(image.width) - width) <= 1, "\(image.width) ≠ \(width)")
        #expect(abs(CGFloat(image.height) - (inner.height + (rim + pad) * 2)) <= 1)
    }

    // MARK: - フェルトの上の読みやすさ

    /// 白を `alpha` でフェルトの中央色に重ねたときの色。
    private static func whiteOverFelt(alpha: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let base = Double((CardTableStyle.feltCenter >> shift) & 0xFF)
            return UInt32((alpha * 255 + (1 - alpha) * base).rounded())
        }
        return channel(16) << 16 | channel(8) << 8 | channel(0)
    }

    @Test("空き枠の破線・印と仕切りは、いちばん明るい中央のフェルトに対して 3:1 以上（非テキストの UI）")
    func slotInkIsVisibleOnTheFelt() {
        for alpha in [CardTableStyle.feltSlotAlpha, CardTableStyle.feltDividerAlpha] {
            let blended = Self.whiteOverFelt(alpha: alpha)
            #expect(WCAG.contrast(blended, CardTableStyle.feltCenter) >= 3.0,
                    "白 \(alpha) はフェルトに沈む（\(WCAG.contrast(blended, CardTableStyle.feltCenter))）")
        }
    }

    @Test("卓の上の文字は、いちばん明るい中央のフェルトに対して AA（4.5:1）以上")
    func labelInkMeetsAAOnTheFelt() {
        for alpha in [CardTableStyle.feltLabelAlpha, CardTableStyle.feltLabelSubAlpha] {
            let blended = Self.whiteOverFelt(alpha: alpha)
            #expect(WCAG.contrast(blended, CardTableStyle.feltCenter) >= 4.5,
                    "白 \(alpha) の文字はフェルトの上で AA 未達（\(WCAG.contrast(blended, CardTableStyle.feltCenter))）")
        }
    }

    @Test("フェルトの縁は中央より暗い（照りの向き。中央が最も明るいので上の検査は最悪値を見ている）")
    func feltEdgeIsDarkerThanTheCenter() {
        #expect(WCAG.relativeLuminance(CardTableStyle.feltEdge) < WCAG.relativeLuminance(CardTableStyle.feltCenter))
    }

    @Test("地の上の既定の色は従来の値（卓の無い画面の見た目を変えない）")
    func plainInkKeepsTheLegacyValues() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/CardTable.swift"))
        // `plain` の定義は波括弧を持たないので、次の定義（`felt`）までを切り出す。
        // `CardTableStyle.feltCenter` などに先に当たらないよう、代入まで含めて探す。
        let start = try #require(source.range(of: "public static let plain = CardTableInk("))
        let end = try #require(source.range(of: "public static let felt = CardTableInk("))
        #expect(start.lowerBound < end.lowerBound, "plain と felt の並びが変わった")
        let plain = String(source[start.lowerBound..<end.lowerBound])
        #expect(plain.contains("Theme.inkSub.opacity(0.35)"), "空き枠の破線の既定が変わった")
        #expect(plain.contains("Theme.inkSub.opacity(0.45)"), "空き枠の印の既定が変わった")
        #expect(plain.contains("Theme.inkSub.opacity(0.5)"), "仕切りの既定が変わった")
    }

    // MARK: - 受け入れ条件: 4 本が同じ卓に乗っている

    @Test("4 本が共通の卓（cardTable）を使い、ゲームごとの卓を作っていない", arguments: [
        "GameSolitaire", "GameSpider", "GameFreeCell", "GameMahjongSolitaire",
    ])
    func everyGameSitsOnTheSharedTable(module: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        #expect(SourceScan.matchCount(of: "\\.cardTable\\(", in: source) == 1,
                "\(module) が卓を 1 か所で付けていない（0 = 卓が無い / 2 以上 = 二重）")
        #expect(!source.contains("CardTableSurface("), "\(module) が卓の面を直接組み立てている")
        #expect(!source.contains("EllipticalGradient"), "\(module) にフェルトの描画が直書きされている")
    }

    /// #1535: 麻雀（4 人打ち）も同じ部品で卓を描く。以前は `MahjongTableSurface` が `Canvas` に木枠と
    /// フェルトを自前で描いていた（色の値も 5 つ直書き）。
    @Test("麻雀（4 人打ち）は共通の卓の部品を使い、独自の卓を描いていない")
    func mahjongSitsOnTheSharedTable() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameMahjong"))
        #expect(SourceScan.matchCount(of: "CardTableSurface\\(frame: MahjongTableLayout\\.tableFrame\\)", in: source) == 1,
                "麻雀の卓が共通の部品で描かれていない")
        #expect(!source.contains("MahjongTableSurface"), "麻雀独自の卓の面が残っている")
        #expect(!source.contains("layout.woodFrame"), "木枠を麻雀側で描いている")
        #expect(!source.contains("layout.felt"), "フェルトを麻雀側で描いている")
        #expect(!source.contains(".radialGradient("), "フェルトの照りを麻雀側で描いている")
    }

    /// 環境値は祖先から子孫へしか流れない。`.cardTable()` は盤（子）に付くので、画面の View 本体が
    /// `@Environment(\.cardTableInk)` を持っても既定の `.plain` しか届かず、フェルトの上に地の色が
    /// 乗る（verifier が最小構成で再現。フリーセルの仕切りと麻雀ソリティアのクリア文字で実際に起きた）。
    @Test("卓の上の色は画面の View 本体で読まず、盤の中の子 View（CardTableInkReader）で読む", arguments: [
        "GameSolitaire", "GameSpider", "GameFreeCell", "GameMahjongSolitaire",
    ])
    func tableInkIsReadInsideTheTable(module: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        #expect(!source.contains("@Environment(\\.cardTableInk)"),
                "\(module) が画面の View 本体で cardTableInk を読んでいる（盤に付けた卓の値は届かない）")
        // 卓の上に色の要る部品を持つゲームは、器を通して読む。麻雀ソリティアのクリア表示は共通の
        // `GameClearCard`（素材の上に Theme.ink で描く）になり、卓の色を読まなくなった（#1755）。
        if module == "GameFreeCell" {
            #expect(source.contains("CardTableInkReader {"), "\(module) が CardTableInkReader を使っていない")
        }
    }

    /// 会長 QA（2026-09-28）: 札が卓の一番上に張り付いて見えるので、札の 3 本は**卓の中の上**に余白を足し、
    /// **3 本で同じ値**にそろえる。ゲームごとに数値を持つと 1 本だけずれる。麻雀ソリティアは対象外。
    @Test("札の 3 本は卓の中の上の余白を共通の値（cardTopInset）で取る", arguments: [
        "GameSolitaire/SolitaireView.swift", "GameSpider/SpiderView.swift", "GameFreeCell/FreeCellView.swift",
    ])
    func cardGamesShareTheTableTopInset(path: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/\(path)"))
        #expect(SourceScan.matchCount(of: "\\.cardTable\\(topInset: CardTableStyle\\.cardTopInset\\)", in: source) == 1,
                "\(path) が卓の中の共通の上の余白を使っていない")
        #expect(CardTableStyle.cardTopInset > 0)
    }

    @Test("空き枠は色を直書きせず、卓の上かどうかを環境値から受け取る")
    func cardSlotReadsInkFromTheEnvironment() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/CardTable.swift"))
        let slot = try #require(SourceScan.declaration(of: "public struct CardSlot", in: source))
        #expect(slot.contains("cardTableInk"), "空き枠が卓の色を読んでいない")
        #expect(!slot.contains("Theme.inkSub"), "空き枠に地の色が直書きされている（フェルトの上で沈む）")
    }

    @Test("卓の修飾子は木枠と余白ぶん中身を縮め、フェルト用の色を配る")
    func tableModifierInsetsContentAndProvidesFeltInk() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/CardTable.swift"))
        let modifier = try #require(SourceScan.declaration(of: "func cardTable(", in: source))
        #expect(modifier.contains("CardTableInsetLayout("))
        #expect(modifier.contains("CardTableStyle.contentInset"))
        #expect(modifier.contains("CardTableSurface(frame:"))
        #expect(modifier.contains(".environment(\\.cardTableInk, .felt)"))
    }
}
