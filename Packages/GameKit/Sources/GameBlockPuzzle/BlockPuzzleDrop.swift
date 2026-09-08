import CoreGraphics

/// ドラッグ位置を盤のマスへ翻訳する幾何計算。
///
/// View から切り出してあるのは、**指の位置とピースの左上マスのずれ**がこのゲームの操作感を
/// そのまま決めるため。ここが 1 マスずれると「置いたつもりの場所と違う場所に置かれる」ので、
/// シミュレータを起動せずに数値で固定できるようにしている。
public enum BlockPuzzleDrop {
    /// 指の位置からピースの中心までの持ち上げ量（セル何個ぶん上に描くか）。
    ///
    /// 指の真下にピースを描くと、置き先のマスが指で隠れて見えない。1.5 マスぶん上へずらすと
    /// 3×3 のピースでも下端が指の上に来る。
    public static let liftInCells: CGFloat = 1.5

    /// ドラッグ中のピースの中心（盤の内側の左上を原点とする座標）。
    ///
    /// - Parameter touch: 指の位置（同じ原点）。
    public static func pieceCenter(touch: CGPoint, cellSize: CGFloat) -> CGPoint {
        CGPoint(x: touch.x, y: touch.y - liftInCells * cellSize)
    }

    /// ピースの中心から、左上マスの行・列を求める。
    ///
    /// 盤の外へはみ出す値もそのまま返す（置けるかどうかの判定は `BlockPuzzleBoard.canPlace` の仕事で、
    /// ここで丸めて盤の中へ寄せてしまうと「外へ落としたのに端に置かれる」ことになる）。
    public static func targetCell(
        center: CGPoint,
        piece: BlockPuzzlePiece,
        cellSize: CGFloat
    ) -> (row: Int, col: Int) {
        guard cellSize > 0 else { return (0, 0) }
        let originX = center.x - CGFloat(piece.width) * cellSize / 2
        let originY = center.y - CGFloat(piece.height) * cellSize / 2
        return (Int((originY / cellSize).rounded()), Int((originX / cellSize).rounded()))
    }
}
