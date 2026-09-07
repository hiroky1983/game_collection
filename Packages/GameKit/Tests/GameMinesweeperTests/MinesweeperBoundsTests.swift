import Testing
import Foundation
@testable import GameMinesweeper

// MARK: - 盤サイズ縮小時の範囲外アクセス（#489）

/// 実ユーザーのクラッシュ（EXC_BREAKPOINT・v1.1.2(7)・iPhone 16 / iOS 26.6）の再発防止。
///
/// 盤サイズが**縮む**変更（上級 16×30 → 初級 9×9 の難易度切り替えなど）が起きると、
/// SwiftUI の差分更新（`ForEachChild.updateValue`）が**旧盤面の添字のまま生きている
/// 子クロージャを新しい小さい `cells` に対して評価する**瞬間がある。差分更新のタイミングには
/// アプリ側から介入できないため、**添字を受け取る側**（モデルの公開 API）が範囲外を
/// 弾けることを固定する。View の `cellView` はこの `cell(atRow:col:)` が `nil` を返すことに
/// 依存して空のマスを描く。
@Suite("マインスイーパー 盤の範囲外アクセス（#489）")
@MainActor
struct MinesweeperBoundsTests {

    /// 縮小後の盤に対して**旧盤面の添字**でアクセスするパスを固定する。
    /// 16×30 は上級、9×9 は初級で、実際に起きた縮小の組み合わせ。
    @Test("盤を大→小に変えたあと、旧盤面の添字で読んでも範囲外アクセスにならない")
    func shrinkingBoardKeepsOldIndicesSafe() {
        let model = MinesweeperModel(rows: 16, cols: 30, mines: 99)
        #expect(model.cell(atRow: 15, col: 29) != nil, "縮小前は盤の内側")

        model.newGame(rows: 9, cols: 9, mines: 10)

        // 旧盤面にしか存在しない添字。ガードが無いと `cells[15][29]` でトラップする。
        #expect(model.cell(atRow: 15, col: 29) == nil)
        #expect(model.cell(atRow: 9, col: 0) == nil, "行だけはみ出す")
        #expect(model.cell(atRow: 0, col: 9) == nil, "列だけはみ出す")
        #expect(model.cell(atRow: 8, col: 8) != nil, "新しい盤の内側は今までどおり読める")
    }

    @Test("負の添字も範囲外として弾く")
    func negativeIndicesAreOutOfBounds() {
        let model = MinesweeperModel(rows: 9, cols: 9, mines: 10)
        #expect(model.cell(atRow: -1, col: 0) == nil)
        #expect(model.cell(atRow: 0, col: -1) == nil)
        #expect(!model.contains(row: -1, col: -1))
        #expect(model.contains(row: 0, col: 0))
    }

    /// `cellView` は本体を描くのと同じ body 評価の中でこの3つも呼ぶ（VoiceOver のヒント・
    /// 近道アクション）。ここが守られていないと、`cell(atRow:col:)` だけ直しても同じ場所で落ちる。
    @Test("可否判定は旧盤面の添字に対して false を返す（trap しない）")
    func capabilityChecksAreSafeAfterShrink() {
        let model = MinesweeperModel(rows: 16, cols: 30, mines: 99)
        model.newGame(rows: 9, cols: 9, mines: 10)

        #expect(!model.canReveal(row: 15, col: 29))
        #expect(!model.canToggleFlag(row: 15, col: 29))
        #expect(!model.canChord(row: 15, col: 29))
    }

    /// 旧盤面の添字を握ったジェスチャが縮小直後に発火しても、盤を壊さず黙って無視する。
    @Test("旧盤面の添字での tap / toggleFlag は盤を変えない")
    func gesturesWithStaleIndicesAreIgnored() {
        let model = MinesweeperModel(rows: 16, cols: 30, mines: 99)
        model.newGame(rows: 9, cols: 9, mines: 10)

        model.tap(row: 15, col: 29)
        model.toggleFlag(row: 15, col: 29)

        #expect(model.gameState == .idle, "盤外のタップで1プレイが始まってしまわない")
        #expect(model.revealedCount == 0)
        #expect(model.flagCount == 0)
    }
}
