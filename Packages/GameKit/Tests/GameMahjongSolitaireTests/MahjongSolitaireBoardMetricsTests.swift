import Testing
import CoreGraphics
import Foundation
import Core
import GameKitTestSupport
@testable import GameMahjongSolitaire

/// 盤面の大きさ（#196）。牌のタップ標的が Apple HIG の 44pt を満たすかを、
/// シミュレータを立てずに実寸で検証する。
///
/// 対応 OS は iOS 17 以上なので、いちばん狭い実機は **iPhone SE 第2/第3世代（375pt 幅）**。
@Suite("麻雀ソリティアの盤面の大きさ")
struct MahjongSolitaireBoardMetricsTests {

    /// 盤面領域（ステータスバーのカード下端〜操作カード上端）。
    /// `docs/ui-review/197/README.md` で実測した値と同じものを使う。
    /// #196 の実測（SE 346.5pt / iPhone 17 Pro 467.7pt）から 2.5pt / 2.4pt 縮んでいるのは、
    /// 表示切り替えボタンを 44pt にしてステータスバーの帯がそのぶん高くなったため（#197）。
    static let iPhoneSE = CGSize(width: 375, height: 344.0)
    static let iPhone17 = CGSize(width: 402, height: 465.3)

    typealias Metrics = MahjongSolitaireBoardMetrics

    @Test("盤面は横 15.56 枚・縦 8.56 枚ぶんの広さ")
    func canvasExtent() {
        #expect(abs(Metrics.canvasWidthInTiles(layout: .turtle) - 15.56) < 0.001)
        #expect(abs(Metrics.canvasHeightInTiles(layout: .turtle) - 8.56) < 0.001)
    }

    @Test(
        "既定の牌は最小タップ標的 44pt 以上",
        arguments: [iPhoneSE, iPhone17]
    )
    func comfortableTileMeetsTapTarget(size: CGSize) {
        let width = Metrics.comfortableTileWidth(in: size, layout: .turtle)
        #expect(width >= 44)
        // 縦横比のぶん高さはさらに大きい。
        #expect(width * Metrics.tileAspect >= 44)
    }

    @Test(
        "全体表示にすると牌は 44pt を割る（両立しないことの記録）",
        arguments: [iPhoneSE, iPhone17]
    )
    func fittingTileIsBelowTapTargetOnPhones(size: CGSize) {
        // 44pt の牌で盤面全体を出すには 684.6pt の幅が要る。iPhone では成立しないため
        // 「全体表示を既定に戻す」と #196 の受け入れ条件を満たせなくなる。この関係が崩れたら気づけるようにする。
        #expect(Metrics.fittingTileWidth(in: size, layout: .turtle) < 44)
        #expect(44 * Metrics.canvasWidthInTiles(layout: .turtle) > 680)
    }

    @Test("全体表示では盤面が与えられた領域に収まる", arguments: [iPhoneSE, iPhone17])
    func fittingCanvasFitsInside(size: CGSize) {
        let canvas = Metrics.canvasSize(
            tileWidth: Metrics.fittingTileWidth(in: size, layout: .turtle),
            layout: .turtle
        )
        #expect(canvas.width <= size.width + 0.001)
        #expect(canvas.height <= size.height + 0.001)
    }

    @Test("画面が広ければ既定の牌は全体表示と同じ大きさ（44pt へ切り下げない）")
    func comfortableNeverShrinksBelowFitting() {
        // iPad 相当。全体表示のままで 44pt を超えるので、拡大が縮小になってはいけない。
        let iPad = CGSize(width: 1024, height: 1200)
        let fitting = Metrics.fittingTileWidth(in: iPad, layout: .turtle)
        #expect(fitting > 44)
        #expect(Metrics.comfortableTileWidth(in: iPad, layout: .turtle) == fitting)
    }

    @Test("既定の牌の幅は全体表示を下回らない", arguments: [iPhoneSE, iPhone17])
    func comfortableIsNeverSmallerThanFitting(size: CGSize) {
        #expect(Metrics.comfortableTileWidth(in: size, layout: .turtle) >= Metrics.fittingTileWidth(in: size, layout: .turtle))
    }

    @Test("同じ段の牌どうしは重ならない（44pt の枠がそのままタップ標的になる）")
    func tilesOnTheSameLayerDoNotOverlap() {
        let tileWidth = Metrics.comfortableTileWidth(in: Self.iPhoneSE, layout: .turtle)
        let layout = MahjongSolitaireLayout.turtle.positions
        for i in layout.indices {
            let a = Metrics.tileFrame(index: i, tileWidth: tileWidth, layout: .turtle)
            #expect(a.width >= 44)
            for j in layout.indices where j > i && layout[j].layer == layout[i].layer {
                let b = Metrics.tileFrame(index: j, tileWidth: tileWidth, layout: .turtle)
                // 接するのは可（幅ちょうどで隣り合う）。食い込んだら別の牌を押してしまう。
                #expect(a.insetBy(dx: 0.001, dy: 0.001).intersects(b) == false)
            }
        }
    }

    // MARK: - 盤面のかたちを増やしても崩れないこと（#239）

    /// #239 の受け入れ条件が挙げている最小幅。実際に対応する最小の実機（SE 第2/第3世代）は
    /// 375pt だが、それより狭い 320pt でも割らないことを見ておく。
    static let narrowest = CGSize(width: 320, height: 300)

    @Test(
        "どのかたちでも既定の牌は 44pt を割らず、同じ段の牌どうしが食い込まない",
        arguments: MahjongSolitaireLayout.all
    )
    func everyLayoutKeepsTheTapTarget(layout: MahjongSolitaireLayout) {
        let tileWidth = Metrics.comfortableTileWidth(in: Self.narrowest, layout: layout)
        #expect(tileWidth >= Metrics.minimumTapTarget, "\(layout.displayName) の牌が 44pt を割る")

        let positions = layout.positions
        for i in positions.indices {
            let a = Metrics.tileFrame(index: i, tileWidth: tileWidth, layout: layout)
            #expect(a.width >= Metrics.minimumTapTarget)
            #expect(a.height >= Metrics.minimumTapTarget)
            for j in positions.indices where j > i && positions[j].layer == positions[i].layer {
                let b = Metrics.tileFrame(index: j, tileWidth: tileWidth, layout: layout)
                // 接するのは可（幅ちょうどで隣り合う）。食い込んだら別の牌を押してしまう。
                #expect(
                    a.insetBy(dx: 0.001, dy: 0.001).intersects(b) == false,
                    "\(layout.displayName) の \(positions[i]) と \(positions[j]) が食い込んでいる"
                )
            }
        }
    }

    @Test("どのかたちでも牌の矩形は盤面の枠に収まる", arguments: MahjongSolitaireLayout.all)
    func everyLayoutFitsInsideItsCanvas(layout: MahjongSolitaireLayout) {
        let tileWidth: CGFloat = 44
        let canvas = Metrics.canvasSize(tileWidth: tileWidth, layout: layout)
        for index in layout.positions.indices {
            let frame = Metrics.tileFrame(index: index, tileWidth: tileWidth, layout: layout)
            #expect(frame.minX >= -0.001, "\(layout.displayName) の \(index) が左にはみ出す")
            #expect(frame.minY >= -0.001, "\(layout.displayName) の \(index) が上にはみ出す")
            #expect(frame.maxX <= canvas.width + 0.001, "\(layout.displayName) の \(index) が右にはみ出す")
            #expect(frame.maxY <= canvas.height + 0.001, "\(layout.displayName) の \(index) が下にはみ出す")
        }
    }

    @Test("どのかたちでも全体表示なら与えられた領域に収まる", arguments: MahjongSolitaireLayout.all)
    func everyLayoutFitsWhenShowingTheWholeBoard(layout: MahjongSolitaireLayout) {
        for size in [Self.narrowest, Self.iPhoneSE, Self.iPhone17] {
            let canvas = Metrics.canvasSize(
                tileWidth: Metrics.fittingTileWidth(in: size, layout: layout),
                layout: layout
            )
            #expect(canvas.width <= size.width + 0.001, "\(layout.displayName) が横にはみ出す")
            #expect(canvas.height <= size.height + 0.001, "\(layout.displayName) が縦にはみ出す")
        }
    }

    // MARK: - 操作は右下の「⋯」へ（#1468）

    @Test("状態の帯にボタン・トグルは無い。全体表示⇄拡大は「⋯」のチェック付き項目")
    func displayToggleLivesInTheMenu() throws {
        let source = SourceScan.strippingComments(try Self.viewSource())
        #expect(!source.contains("BoardToggleButton("), "帯に切り替えボタンが残っている")
        #expect(source.contains(#"GameControlMenuItem("#))
        #expect(source.contains(#"id: "zoom""#))
        #expect(SourceScan.matchCount(of: #"GameOverflowBar\("#, in: source) == 1)
    }

    // MARK: - 操作ボタンと演出（#199）

    @Test("戻す・並べ替え・ヒントは「⋯」メニューに入っていて、画面ごとの手描きボタンは無い")
    func controlsLiveInTheMenu() throws {
        let source = SourceScan.strippingComments(try Self.viewSource())
        for id in ["undo", "shuffle", "hint"] {
            #expect(source.contains("id: \"\(id)\""), "\(id) が「⋯」メニューに無い")
        }
        #expect(SourceScan.matchCount(of: #"controlButton\("#, in: source) == 0)
        #expect(SourceScan.matchCount(of: #"GameControlButton\("#, in: source) == 0)
    }

    @Test("牌の消失・枠色の演出は Reduce Motion 追従のヘルパー経由で盤面に掛かっている")
    func boardAnimationIsWiredThroughMotionHelper() throws {
        let source = try Self.viewSource()
        // 素の `withAnimation` / `.animation(` を使っていないことは `MotionTests` が全ソースで見ている。
        // ここでは「盤面に演出が**掛かっている**」ことを見る（消しても他のテストは赤くならないため）。
        #expect(
            source.range(
                of: #"\.gameAnimation\(.*value:\s*boardAnimationKey\)"#,
                options: .regularExpression
            ) != nil,
            "盤面に .gameAnimation(_:value: boardAnimationKey) が掛かっていない"
        )
        #expect(
            source.range(of: #"\.transition\("#, options: .regularExpression) != nil,
            "牌に .transition( が無い（取った牌が即座に消える）"
        )
    }

    @Test("最後の1組が消えきってからクリア表示に切り替わる")
    func clearDisplayWaitsForTheLastPairToVanish() throws {
        // `tap(_:)` は最後の 1 組の `faces` を nil にしたのと**同じ更新**で `phase` を `.won` にする。
        // 盤面が `model.phase` を直に見ていると、そこで盤面ごとクリア表示に差し替わり、
        // 最後の 2 枚だけ消失アニメーションが出ないまま終わる（CodeRabbit の指摘・#235）。
        let source = try Self.viewSource()
        #expect(
            source.range(of: #"if showsClearDisplay \{"#, options: .regularExpression) != nil,
            "盤面が model.phase を直に見ている（最後の2枚の演出が飛ぶ）"
        )
        // 演出の長さと待ち時間が別々の値になると、消えきる前に差し替わる/消えた後に間が空く。
        #expect(
            SourceScan.matchCount(of: #"Metrics\.boardAnimationDuration"#, in: source) >= 2,
            "演出の長さと待ち時間が同じ定数から来ていない"
        )
        #expect(Metrics.boardAnimationDuration > 0)
    }

    @Test("牌の transition は offset より前に置かれている")
    func tileTransitionComesBeforeOffset() throws {
        // `.offset` は牌のレイアウト上の位置（盤面の左上）を動かさないため、`.transition` を
        // `.offset` より後ろに置くと縮小の基準が牌の中心ではなく盤面の左上になり、
        // 消える牌が左上へ吸い込まれる。順序が入れ替わっても画面を見るまで気づけないので固定する。
        let source = try Self.viewSource()
        let transition = try #require(source.range(of: #"\.transition\("#, options: .regularExpression))
        let offset = try #require(source.range(of: #"\.offset\(x:\s*frame\.minX"#, options: .regularExpression))
        #expect(transition.lowerBound < offset.lowerBound)
    }

    /// View のソースを読む。`#filePath` からの相対で辿るので、パスの導出が壊れたら投げる。
    private static func viewSource() throws -> String {
        try SourceScan.packageSource("Sources/GameMahjongSolitaire/MahjongSolitaireView.swift")
    }

    @Test("牌の矩形は盤面の枠に収まる")
    func tileFramesStayInsideCanvas() {
        let tileWidth: CGFloat = 44
        let canvas = Metrics.canvasSize(tileWidth: tileWidth, layout: .turtle)
        for index in MahjongSolitaireLayout.turtle.positions.indices {
            let frame = Metrics.tileFrame(index: index, tileWidth: tileWidth, layout: .turtle)
            #expect(frame.minX >= -0.001)
            #expect(frame.minY >= -0.001)
            #expect(frame.maxX <= canvas.width + 0.001)
            #expect(frame.maxY <= canvas.height + 0.001)
        }
    }
}
