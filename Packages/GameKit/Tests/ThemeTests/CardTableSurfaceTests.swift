import Testing
import Foundation
import CoreGraphics
import Core
import GameKitTestSupport

/// 卓の面（#1501）を固定する。
///
/// 4 本（ソリティア・スパイダー・フリーセル・麻雀ソリティア）が**同じ 1 つの卓**に乗っていること、
/// 卓の色が雀卓（`MahjongTableSurface`）と同じ値でアプリ全体で浮かないこと、フェルトの上に置く
/// 空き枠・文字が読めること（コントラスト）を、数値とソースの 2 方向から見る。
@Suite("卓の面")
struct CardTableSurfaceTests {

    // MARK: - 雀卓と同じ色

    @Test("フェルトと木枠の色は雀卓（MahjongTableSurface）と同じ値")
    func feltAndRimMatchTheMahjongTable() throws {
        let source = try SourceScan.packageSource("Sources/GameMahjong/MahjongTableView.swift")
        let surface = try #require(SourceScan.declaration(of: "struct MahjongTableSurface", in: source))
        for hex in [CardTableStyle.feltCenter, CardTableStyle.feltEdge,
                    CardTableStyle.rimTop, CardTableStyle.rimMiddle, CardTableStyle.rimBottom] {
            let literal = String(format: "0x%06X", hex)
            #expect(surface.contains(literal), "雀卓に \(literal) が無い。卓の色が雀卓から離れている")
        }
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
        #expect(SourceScan.matchCount(of: "\\.cardTable\\(\\)", in: source) == 1,
                "\(module) が卓を 1 か所で付けていない（0 = 卓が無い / 2 以上 = 二重）")
        #expect(!source.contains("CardTableSurface("), "\(module) が卓の面を直接組み立てている")
        #expect(!source.contains("EllipticalGradient"), "\(module) にフェルトの描画が直書きされている")
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
        // 卓の上に色の要る部品を持つゲームは、器を通して読む。
        if module == "GameFreeCell" || module == "GameMahjongSolitaire" {
            #expect(source.contains("CardTableInkReader {"), "\(module) が CardTableInkReader を使っていない")
        }
    }

    /// 会長 QA（2026-09-28）: 帯と卓が画面の上に詰まって見えるので、札の 3 本は上の余白を少し広げ、
    /// **3 本で同じ値**にそろえる。ゲームごとに数値を持つと 1 本だけずれる。
    @Test("札の 3 本は画面の上の余白を共通の値（screenTopPadding）で取る", arguments: [
        "GameSolitaire/SolitaireView.swift", "GameSpider/SpiderView.swift", "GameFreeCell/FreeCellView.swift",
    ])
    func cardGamesShareTheTopPadding(path: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/\(path)"))
        #expect(SourceScan.matchCount(of: "\\.padding\\(\\.top, CardTableStyle\\.screenTopPadding\\)", in: source) == 1,
                "\(path) が共通の上の余白を使っていない")
        #expect(!source.contains(".padding(.vertical, Theme.pad)"), "\(path) の上の余白が地の 16pt のまま")
        #expect(CardTableStyle.screenTopPadding > Theme.pad)
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
        let modifier = try #require(SourceScan.declaration(of: "func cardTable()", in: source))
        #expect(modifier.contains("CardTableStyle.rimWidth + CardTableStyle.contentInset"))
        #expect(modifier.contains(".environment(\\.cardTableInk, .felt)"))
    }
}
