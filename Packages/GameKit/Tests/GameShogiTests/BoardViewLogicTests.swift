import Testing
@testable import GameShogi

@Suite("盤の向き（先手視点／後手反転）")
struct BoardOrientationTests {
    @Test func senteViewTopLeftIs9a() {
        // 反転なし: 左上 = 9筋a段、右下 = 1筋i段。
        #expect(Sq.boardIndex(row: 0, col: 0, flipped: false) == Sq.fromUSI("9a")!)
        #expect(Sq.boardIndex(row: 8, col: 8, flipped: false) == Sq.fromUSI("1i")!)
    }

    @Test func goteViewIsFlipped180() {
        // 反転: 後手が手前。左上 = 1筋i段（先手視点の右下が来る）。
        #expect(Sq.boardIndex(row: 0, col: 0, flipped: true) == Sq.fromUSI("1i")!)
        #expect(Sq.boardIndex(row: 8, col: 8, flipped: true) == Sq.fromUSI("9a")!)
    }

    @Test func everyCellMapsToUniqueSquare() {
        for flipped in [false, true] {
            var seen = Set<Int>()
            for row in 0..<9 { for col in 0..<9 {
                seen.insert(Sq.boardIndex(row: row, col: col, flipped: flipped))
            }}
            #expect(seen.count == 81)
        }
    }
}

@MainActor
@Suite("直前手のハイライト・表記")
struct LastMoveTests {
    @Test func highlightsLastMoveSquaresAndText() {
        let model = ShogiGameModel(services: nil)
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        // 移動元・先がハイライト対象。
        #expect(model.highlightedSquares == [Sq.fromUSI("7g")!, Sq.fromUSI("7f")!])
        // 棋譜表記は先手の手なので ▲ で始まり「歩」を含む。
        let text = model.highlightedMoveText
        #expect(text?.hasPrefix("▲") == true)
        #expect(text?.contains("歩") == true)
    }

    @Test func noHighlightAtGameStart() {
        let model = ShogiGameModel(services: nil)
        #expect(model.highlightedMove == nil)
        #expect(model.highlightedSquares.isEmpty)
        #expect(model.highlightedMoveText == nil)
    }
}
