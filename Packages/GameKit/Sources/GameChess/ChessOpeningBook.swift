import Foundation

/// 簡易定跡ブック。代表的な出だし手順を「局面(FEN) → 次の一手(UCI)」として持つ。
///
/// 手順の定義から初期局面を再生して構築するので、非合法手は構築時に自動で打ち切られる
/// （将棋の `OpeningBook` と同じ作り）。定跡そのものは何百年も公知の手順で、
/// 特定の実装から取り込んだデータではない（#462 の権利確認）。
enum ChessOpeningBook {
    /// 局面 FEN に対する定跡手（無ければ nil）。
    static func move(for fen: String) -> String? { table[key(for: fen)] }

    /// 引き当てのキー。**手数（FEN の 5・6 番目）は落とす**。同じ局面へ別の手順で
    /// 合流したときにも定跡が効くようにするため。
    private static func key(for fen: String) -> String {
        fen.split(separator: " ").prefix(4).joined(separator: " ")
    }

    /// 代表的な主要変化。白番・黒番のどちらの手番ぶんも含む。
    private static let lines: [[String]] = [
        // イタリアンゲーム
        ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "c2c3", "g8f6", "d2d3", "d7d6"],
        // ルイ・ロペス
        ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5a4", "g8f6", "e1g1", "f8e7"],
        // シシリアン・ディフェンス
        ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3", "a7a6"],
        // フレンチ・ディフェンス
        ["e2e4", "e7e6", "d2d4", "d7d5", "b1c3", "g8f6", "c1g5", "f8e7"],
        // カロ・カン
        ["e2e4", "c7c6", "d2d4", "d7d5", "b1c3", "d5e4", "c3e4", "c8f5"],
        // クイーンズギャンビット
        ["d2d4", "d7d5", "c2c4", "e7e6", "b1c3", "g8f6", "c1g5", "f8e7", "e2e3", "e8g8"],
        // インディアン・ディフェンス（キングズ・インディアン）
        ["d2d4", "g8f6", "c2c4", "g7g6", "b1c3", "f8g7", "e2e4", "d7d6", "g1f3", "e8g8"],
        // イングリッシュ・オープニング
        ["c2c4", "e7e5", "b1c3", "g8f6", "g1f3", "b8c6", "g2g3", "d7d5"],
    ]

    private static let table: [String: String] = {
        var dict: [String: String] = [:]
        for line in lines {
            var pos = ChessPosition.start()
            for uci in line {
                guard let move = ChessMove.fromUCI(uci),
                      pos.legalMoves().contains(move) else { break }
                let k = key(for: pos.toFEN())
                if dict[k] == nil { dict[k] = uci } // 先に登録した手を優先
                pos.make(move)
            }
        }
        return dict
    }()
}
