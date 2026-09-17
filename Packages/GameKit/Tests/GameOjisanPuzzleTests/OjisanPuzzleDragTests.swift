import Testing
import CoreGraphics
@testable import GameOjisanPuzzle

/// スワイプの翻訳（会長指示 2026-09-17 でボタンを廃してスワイプ操作にしたぶん）。
///
/// 指の移動量とマスの対応が狂うと「1 回のスワイプで 2 マス飛ぶ」「押しても動かない」になるので、
/// シミュレータを起動せずにここで固定する。
@Suite("スワイプの翻訳")
struct OjisanPuzzleDragTests {
    private let cell: CGFloat = 40

    @Test("1 マスぶん動かすまでは動かない")
    func doesNotMoveBelowOneCell() {
        #expect(OjisanPuzzleDrag.steps(0, step: cell) == 0)
        #expect(OjisanPuzzleDrag.steps(cell - 1, step: cell) == 0)
        #expect(OjisanPuzzleDrag.steps(-(cell - 1), step: cell) == 0)
    }

    @Test("1 マスぶん動かすと 1 マス。端数は切り捨て")
    func movesOneCellPerStep() {
        #expect(OjisanPuzzleDrag.steps(cell, step: cell) == 1)
        #expect(OjisanPuzzleDrag.steps(cell * 1.9, step: cell) == 1)
        #expect(OjisanPuzzleDrag.steps(cell * 3, step: cell) == 3)
    }

    @Test("左は負・右は正")
    func signFollowsDirection() {
        #expect(OjisanPuzzleDrag.steps(-cell * 2, step: cell) == -2)
        #expect(OjisanPuzzleDrag.steps(cell * 2, step: cell) == 2)
    }

    @Test("1 マスぶんの距離が 0 でも落ちない")
    func toleratesZeroStep() {
        #expect(OjisanPuzzleDrag.steps(100, step: 0) == 0)
        #expect(OjisanPuzzleDrag.downSteps(100, step: 0) == 0)
    }

    @Test("上スワイプには何も割り当てない")
    func ignoresUpwardSwipe() {
        #expect(OjisanPuzzleDrag.downSteps(-cell * 3, step: cell) == 0)
        #expect(OjisanPuzzleDrag.downSteps(cell * 3, step: cell) == 3)
    }

    @Test("ほとんど動いていなければタップ（＝回す）")
    func smallMovementIsTap() {
        #expect(OjisanPuzzleDrag.isTap(translation: .zero, movedColumns: 0, movedRows: 0))
        #expect(OjisanPuzzleDrag.isTap(translation: CGSize(width: 3, height: -4), movedColumns: 0, movedRows: 0))
    }

    @Test("大きく動かしたらタップではない")
    func largeMovementIsNotTap() {
        #expect(!OjisanPuzzleDrag.isTap(
            translation: CGSize(width: OjisanPuzzleDrag.tapSlack, height: 0), movedColumns: 0, movedRows: 0
        ))
    }

    /// ゆっくり 1 マス動かして指を元へ戻すと移動量は 0 に近い。ここでマス数を見ていないと
    /// 「動かしたのに回ってしまう」ことになる。
    @Test("1 マスでも動かしていたらタップにはしない")
    func movedCellsDisqualifyTap() {
        #expect(!OjisanPuzzleDrag.isTap(translation: .zero, movedColumns: 1, movedRows: 0))
        #expect(!OjisanPuzzleDrag.isTap(translation: .zero, movedColumns: 0, movedRows: 1))
    }
}
