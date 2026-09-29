import Testing
@testable import GameShogi

/// 玉への大駒・香の利きの素通し（`kingExposure`）を固定局面の**値**で確かめる（#1390）。
///
/// `kingExposure` は `private struct SearchContext` の中にあり直接呼べないので、テスト用の口
/// `kingSafety`（= `kingShelter`）越しに測る。`kingShelter` の他の項（守り駒・端寄せ・自陣の段）は
/// **自分の駒と玉の位置だけ**で決まるため、相手の駒を置いても変わらない。よって
/// `素通しの減点 = 玉の位置だけで決まる基準値 − kingSafety` がそのまま取り出せる。
/// 基準値（守り駒なし）: 5九玉・5一玉は自陣最下段 `max(0, 2 − 0) × 10 = 20`、5五玉は 0。
///
/// 減点は「玉から見て最初にぶつかった相手の駒が、その方向に利く飛・龍（縦横）／角・馬（斜め）／
/// 前向きの香（縦）なら `(9 − 距離) × 6`」の合計。期待値は下の各局面で手で数えた値。
/// SFEN の各段は 9筋 → 1筋 の順で、5筋は `4X4`、1筋は `8X` と書く。先手玉 5九 は rank 8。
@Suite("玉への利きの素通し（kingExposure・#1390）")
struct KingExposureTests {
    private let engine = SimpleMinimaxEngine(level: 1)

    /// 守り駒の無い玉の基準値から `kingSafety` を引いた値 = `kingExposure`。
    private func exposure(_ sfen: String, _ color: Side = .black, base: Int = 20) throws -> Int {
        let pos = try #require(Position.fromSFEN(sfen))
        return base - engine.kingSafety(pos, color)
    }

    @Test("玉だけの局面は 0（相手玉が筋に居ても数えない）。基準値そのものも固定する")
    func bareKingsAreNotExposed() throws {
        let pos = try #require(Position.fromSFEN("4k4/9/9/9/9/9/9/9/4K4 b - 1"))
        #expect(engine.kingSafety(pos, .black) == 20)
        #expect(engine.kingSafety(pos, .white) == 20)
    }

    @Test("同じ筋の相手の飛車は近いほど重い: 距離5 = 24、距離2 = 42")
    func rookOnFileScalesWithDistance() throws {
        // 5四飛（rank 3）→ 5九玉まで 5 マス: (9 − 5) × 6 = 24。
        #expect(try exposure("4k4/9/9/4r4/9/9/9/9/4K4 b - 1") == 24)
        // 5七飛（rank 6）→ 2 マス: (9 − 2) × 6 = 42。
        #expect(try exposure("4k4/9/9/9/9/9/4r4/9/4K4 b - 1") == 42)
    }

    @Test("間に駒があれば遮られて 0（自分の歩でも相手の歩でも）")
    func blockedLineIsNotExposed() throws {
        // 5七の歩は玉から距離2（ring2）だが、ring2 の歩は加点されないので基準値は 20 のまま。
        #expect(try exposure("4k4/9/9/4r4/9/9/4P4/9/4K4 b - 1") == 0)
        #expect(try exposure("4k4/9/9/4r4/9/9/4p4/9/4K4 b - 1") == 0)
    }

    @Test("横の飛車・龍も数える: 1九飛 → 距離4 = 30")
    func rookAndDragonOnRank() throws {
        #expect(try exposure("4k4/9/9/9/9/9/9/9/4K3r b - 1") == 30)
        #expect(try exposure("4k4/9/9/9/9/9/9/9/4K3+r b - 1") == 30)
        // 対照: 自分の飛車は減点しない（距離4 なので守り駒の加点にも入らない）。
        #expect(try exposure("4k4/9/9/9/9/9/9/9/4K3R b - 1") == 0)
    }

    @Test("斜めは角・馬だけ: 1五角 → 距離4 = 30。斜めの飛車・縦の角は 0")
    func bishopOnlyOnDiagonals() throws {
        // 5九玉から 4八・3七・2六・1五 と斜めに 4 マス。
        #expect(try exposure("4k4/9/9/9/8b/9/9/9/4K4 b - 1") == 30)
        #expect(try exposure("4k4/9/9/9/8+b/9/9/9/4K4 b - 1") == 30)
        #expect(try exposure("4k4/9/9/9/8r/9/9/9/4K4 b - 1") == 0)
        #expect(try exposure("4k4/9/9/4b4/9/9/9/9/4K4 b - 1") == 0)
    }

    @Test("香は前向きの利きだけ: 玉の上の後手香は 24、成香・玉の後ろの後手香は 0")
    func lanceOnlyForward() throws {
        // 後手の香は下（rank が増える方）へ利く。5四香 → 5九玉: 距離5 = 24。
        #expect(try exposure("4k4/9/9/4l4/9/9/9/9/4K4 b - 1") == 24)
        // 成香は金の動きなので素通しの利きを持たない。
        #expect(try exposure("4k4/9/9/4+l4/9/9/9/9/4K4 b - 1") == 0)
        // 先手玉 5五（基準値 0）・後手香 5九: 香は玉から遠ざかる向きにしか利かないので 0。
        #expect(try exposure("4k4/9/9/9/4K4/9/9/9/4l4 b - 1", base: 0) == 0)
        // 対照: 同じ場所の飛車なら距離4 = 30。
        #expect(try exposure("4k4/9/9/9/4K4/9/9/9/4r4 b - 1", base: 0) == 30)
    }

    @Test("後手玉から見ても同じ: 5六の先手飛・先手香 → 距離5 = 24")
    func whiteKingPerspective() throws {
        // 後手玉 5一（rank 0）。先手の香は上（rank が減る方）へ利くので玉に向かっている。
        #expect(try exposure("4k4/9/9/9/9/4R4/9/9/4K4 w - 1", .white) == 24)
        #expect(try exposure("4k4/9/9/9/9/4L4/9/9/4K4 w - 1", .white) == 24)
    }

    @Test("複数の方向は足し合わせる: 縦の飛(24) + 斜めの角(30) = 54")
    func multipleLinesAdd() throws {
        #expect(try exposure("4k4/9/9/4r4/8b/9/9/9/4K4 b - 1") == 54)
    }
}
