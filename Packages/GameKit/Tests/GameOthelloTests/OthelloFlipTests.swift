import Testing
import Foundation
@testable import GameOthello

/// 石が裏返る演出の形をシミュレータ抜きで固定する（#204）。
///
/// 反転は `Canvas` の中で描かれるため、目視でしか確認できない形のままだと
/// 「色が瞬間で切り替わるだけ」の元の姿にいつでも戻ってしまう。
/// 進捗 → 見える色・幅の翻訳を `OthelloFlip` の純関数に切り出してあるので、ここで直接押さえる。
@Suite("オセロ 反転演出")
struct OthelloFlipTests {

    // MARK: - 受け入れ条件1: 色が切り替わる反転アニメーションが付く

    /// 折り返し（p = 0.5）を境に、見える色が「返る前」から「返った後」へ入れ替わること。
    /// 盤はすでに着手を反映済みなので、前半は反対の色を描くのが正しい。
    @Test func shownStoneSwitchesAtHalfway() {
        #expect(OthelloFlip.shownStone(target: .black, progress: 0.0) == .white)
        #expect(OthelloFlip.shownStone(target: .black, progress: 0.49) == .white)
        #expect(OthelloFlip.shownStone(target: .black, progress: 0.5) == .black)
        #expect(OthelloFlip.shownStone(target: .black, progress: 1.0) == .black)
        // 白へ返る側も対称であること。
        #expect(OthelloFlip.shownStone(target: .white, progress: 0.0) == .black)
        #expect(OthelloFlip.shownStone(target: .white, progress: 1.0) == .white)
    }

    /// 幅は「実寸 → 折り返しで最も細い → 実寸」と往復すること（縦軸まわりの回転に見える）。
    @Test func widthScaleNarrowsAtHalfwayAndReturns() {
        #expect(abs(OthelloFlip.widthScale(progress: 0) - 1) < 0.0001)
        #expect(abs(OthelloFlip.widthScale(progress: 1) - 1) < 0.0001)

        let middle = OthelloFlip.widthScale(progress: 0.5)
        #expect(middle < OthelloFlip.widthScale(progress: 0.25))
        #expect(middle < OthelloFlip.widthScale(progress: 0.75))
    }

    /// 折り返しでも石が完全には消えないこと。0 まで落とすと 1 フレーム抜けたように見える。
    @Test func widthScaleKeepsThinEdgeAtHalfway() {
        #expect(OthelloFlip.widthScale(progress: 0.5) == OthelloFlip.minimumWidthScale)
        for step in 0...20 {
            #expect(OthelloFlip.widthScale(progress: Double(step) / 20) >= OthelloFlip.minimumWidthScale)
        }
    }

    // MARK: - 受け入れ条件2: 複数方向で同時に反転しても破綻しない

    /// 置いた石に近い順に返り始めること（どの方向へ何枚返ったかが読み取れる）。
    @Test func nearerStonesStartFlippingFirst() {
        let overall = 0.3
        let near = OthelloFlip.progress(distance: 1, overall: overall)
        let far  = OthelloFlip.progress(distance: 4, overall: overall)
        #expect(near > far)
    }

    /// 一方向に返る最大枚数（6 枚）でも、全体の進捗が 1 になった時点で全員が返りきること。
    /// ここが 1 未満だと、遠い石だけ反転中の細い姿で取り残される。
    @Test func farthestStoneFinishesWhenOverallCompletes() {
        for distance in 1...6 {
            #expect(OthelloFlip.progress(distance: distance, overall: 1) == 1)
        }
        // 想定外に遠い距離を渡しても取り残されない（頭打ちが効く）。
        #expect(OthelloFlip.progress(distance: 99, overall: 1) == 1)
    }

    /// 進捗は 0→1 に収まり、始点では誰も返っていないこと。
    @Test func progressStaysInUnitRange() {
        for distance in 1...8 {
            #expect(OthelloFlip.progress(distance: distance, overall: 0) == 0)
            for step in 0...20 {
                let p = OthelloFlip.progress(distance: distance, overall: Double(step) / 20)
                #expect(p >= 0 && p <= 1)
            }
        }
    }

    /// 段差の合計が全体の進捗に収まっていること（`stagger * 5 + span <= 1`）。
    /// ここが崩れると遠い石の反転が尻切れになる。
    @Test func staggerAndSpanFitInOneCycle() {
        #expect(OthelloFlip.stagger * 5 + OthelloFlip.span <= 1.0)
    }

    // MARK: - 受け入れ条件3: CPU 対戦のテンポが過度に長くならない

    /// 演出の長さの上限を固定する（受け入れ条件3）。
    ///
    /// CPU はこの長さだけ着手を遅らせる（読みと並行なので、これが CPU の待ちの上限になる）。
    /// あとから「もっと見せたい」で伸ばされると連続着手のテンポが落ちるため、ここで頭を押さえる。
    @Test func durationStaysShortEnoughForCPUTempo() {
        #expect(OthelloFlip.duration <= 0.4)
        #expect(OthelloFlip.duration >= 0.2) // 短すぎて何が起きたか分からないのも避ける
    }
}

// MARK: - モデルが渡す反転対象

@MainActor
@Suite("オセロ 反転対象の受け渡し")
struct OthelloFlippedCellsTests {

    private func freshModel() -> OthelloModel {
        OthelloModel(services: nil, flipSettleDelay: .zero)
    }

    /// 着手のたびに「その手で返った石」だけが渡ること。置いた石そのものは含まない
    /// （含めると置いた石まで反転中の姿で描かれ、直前手マーカーと二重に動く）。
    @Test func placingReportsFlippedStonesOnly() {
        let model = freshModel()
        // 初期盤面の黒の合法手は4つ。いずれも白1枚だけを返す。
        let move = try! #require(model.board.validMoves(for: .black).first)
        model.tap(row: move.0, col: move.1)

        #expect(model.flippedCells.count == 1)
        #expect(model.flippedCells.contains(move.0 * othelloBoardSize + move.1) == false)
        // 返ったマスは現在 黒 になっている。
        for index in model.flippedCells {
            #expect(model.board[index / othelloBoardSize, index % othelloBoardSize] == .black)
        }
    }

    /// 着手数は石を置いたときだけ増えること。演出の進捗はこの値の変化で駆動するため、
    /// パスや待ったで増えると何も返っていないのに反転演出が走ってしまう。
    @Test func placementCountAdvancesOnlyOnPlacement() {
        let model = freshModel()
        #expect(model.placementCount == 0)

        let first = try! #require(model.board.validMoves(for: .black).first)
        model.tap(row: first.0, col: first.1)
        #expect(model.placementCount == 1)

        // 置けないマスへのタップでは増えない。
        model.tap(row: 0, col: 0)
        #expect(model.placementCount == 1)
    }

    /// 「待った」で盤を戻したら反転対象は消えること。残ると巻き戻した石が反転中の姿で描かれる。
    @Test func undoClearsFlippedCells() async {
        let model = freshModel()
        let first = try! #require(model.board.validMoves(for: .black).first)
        model.tap(row: first.0, col: first.1)
        await model.performAIMoveIfNeeded()
        #expect(model.flippedCells.isEmpty == false)

        model.undoLastExchange()
        #expect(model.flippedCells.isEmpty)
    }

    /// 新規対局でも反転対象は消えること。
    @Test func newGameClearsFlippedCells() {
        let model = freshModel()
        let first = try! #require(model.board.validMoves(for: .black).first)
        model.tap(row: first.0, col: first.1)
        #expect(model.flippedCells.isEmpty == false)

        model.newGame(humanSide: .black)
        #expect(model.flippedCells.isEmpty)
    }
}
