import Foundation

/// ブロックならべの中断スナップショット（#493）。
///
/// 盤・手元・スコアをそのまま保存する。ピースは形ではなく**カタログ番号**で書き、
/// 読むときに範囲を検めるので、壊れたデータで存在しない形が復元されることはない。
/// 乱数の状態は保存しない（次に配るときは新しく引き直せばよい）。
public struct BlockPuzzleSnapshot: Codable, Equatable, Sendable {
    public var board: [[Int]]
    /// 手元 3 スロット。使用済みは nil。値は `BlockPuzzlePiece.catalog` の添字。
    public var hand: [Int?]
    public var score: Int
    /// 連続で消している回数。中断で切れると得点が変わってしまうので保存する。
    public var combo: Int
    /// コンティニュー（広告視聴による復活）を使い切っているか。
    /// これを保存しないと、再起動するだけで同じ局を何度でも復活できてしまう（2048 #122 と同型）。
    public var continueUsed: Bool

    public init(board: [[Int]], hand: [Int?], score: Int, combo: Int = 0, continueUsed: Bool = false) {
        self.board = board
        self.hand = hand
        self.score = score
        self.combo = combo
        self.continueUsed = continueUsed
    }

    /// 復元して使える内容か検める。
    ///
    /// 盤の形・色番号・カタログ番号のいずれかが壊れていたら nil を返し、Model 側は
    /// 新規開始に倒す。`[[Int]]` は JSON からいくらでも別の形で読めてしまうので、
    /// 「復号できた = 遊べる」ではない（#520 と同じ考え方）。
    public func validated() -> (board: [[Int]], hand: [BlockPuzzlePiece?])? {
        guard BlockPuzzleBoard.isValid(board) else { return nil }
        guard hand.count == BlockPuzzleBoard.handSize else { return nil }

        var pieces: [BlockPuzzlePiece?] = []
        for id in hand {
            guard let id else {
                pieces.append(nil)
                continue
            }
            guard let piece = BlockPuzzlePiece.catalogPiece(id: id) else { return nil }
            pieces.append(piece)
        }
        // 3 スロットすべて使用済みの状態は保存されない（置いた直後に必ず配り直すため）。
        guard pieces.contains(where: { $0 != nil }) else { return nil }
        guard score >= 0, combo >= 0 else { return nil }
        return (board, pieces)
    }
}
