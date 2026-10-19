/// 人間と CPU が交互に指す盤ゲームの「続きから」判定の共通部品（#2508）。
///
/// 人間が後手を選ぶと CPU の初手が先に中断データへ入る。その 1 手だけでは人間は何も指していないので、
/// 「続き」にも「手つかず」の例外にもしない。各ゲームは手数の数え方（手順の長さ・石の数）だけを渡す。
public enum CPUOpening {
    /// 人間が少なくとも 1 手指したか。`totalMoves` は両者の合計手数、`cpuMovesFirst` は CPU が先に指す局か。
    public static func humanHasMoved(totalMoves: Int, cpuMovesFirst: Bool) -> Bool {
        totalMoves > (cpuMovesFirst ? 1 : 0)
    }

    /// FEN / SFEN の手番欄（2 つ目）から、先に指すのが後手側（`b` = チェスの黒・`w` = 将棋の後手）か。
    /// 読めない形式は先手側として扱う（平手・標準の開始局面と同じ）。
    public static func startsWithSecondPlayer(fen: String, secondPlayerToken: String) -> Bool {
        let fields = fen.split(separator: " ")
        return fields.count > 1 && fields[1] == secondPlayerToken
    }
}
