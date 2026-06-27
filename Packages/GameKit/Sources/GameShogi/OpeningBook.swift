import Foundation

/// 定跡ブック。「局面(SFEN) → 次の一手(USI)」テーブルを戦型ごとの手順から自動構築する。
/// 手順に非合法手が含まれていても構築時に自動打ち切りされるので安全。
enum OpeningBook {
    static func move(for sfen: String) -> String? { table[sfen] }

    private static let lines: [[String]] = [

        // MARK: - 居飛車系（先手番）

        // 矢倉：玉を右に囲い、金銀を整備する
        ["7g7f", "8c8d", "7i6h", "3c3d",
         "6h7g", "7a6b", "5i4h", "4a3b",
         "4h3h", "3b3c", "3h2h", "5c5d",
         "4i4h", "4c4d", "3i4i", "6b5c",
         "4i5h", "5c4d", "5h6h", "4d3e"],

        // 矢倉：後手が別の応手をした場合
        ["7g7f", "3c3d", "7i6h", "8c8d",
         "6h7g", "4a3b", "5i4h", "3b3c",
         "4h3h", "5c5d", "3h2h", "6a5b",
         "4i4h", "5b4c", "3i4i", "4c5d"],

        // 角換わり：先手が角交換してから棒銀で攻める
        ["7g7f", "8c8d", "2g2f", "8d8e",
         "8h7g", "3c3d", "2b7g+", "7i7g",
         "3i4h", "7a6b", "4h3g", "6b5c",
         "3g2f", "4a3b", "2f2e", "5c4d",
         "2e2d", "2c2d", "8h2b+", "3b2b"],

        // 角換わり：後手が先に角交換を狙う場合
        ["7g7f", "8c8d", "2g2f", "8d8e",
         "8h7g", "3c3d", "7g2b+", "3a2b",
         "3i3h", "4a3b", "3h2g", "7a6b",
         "2g3f", "6b5c", "3f4e", "5c4d"],

        // 相掛かり：飛車先を伸ばして主導権を握る
        ["7g7f", "8c8d", "2g2f", "8d8e",
         "2f2e", "2b3c", "3i3h", "3c2b",
         "3h2g", "7a6b", "2g3f", "6b5c",
         "3f4e", "5c4d", "4e5d", "4d5e"],

        // 横歩取り：飛車で横の歩を取りに行く
        ["7g7f", "8c8d", "2g2f", "8d8e",
         "2f2e", "3c3d", "2e2d", "2c2d",
         "8h2b+", "3a2b", "2i2d", "8b8e",
         "2d2f", "4a3b", "4i3h", "3b4c"],

        // MARK: - 振り飛車系（先手番）

        // 四間飛車：飛車を4筋に振り美濃囲いへ
        ["7g7f", "3c3d", "6g6f", "8c8d",
         "6i6h", "4a3b", "6h4h", "3b3c",
         "5i4i", "5c5d", "4i3i", "6a5b",
         "3i2i", "5b4c", "4h3h", "4c5d"],

        // 四間飛車：後手が居飛車で来た場合
        ["7g7f", "8c8d", "6g6f", "3c3d",
         "6i6h", "7a6b", "6h4h", "6b5c",
         "5i4i", "4a3b", "4i3i", "3b4c",
         "3i2i", "8d8e", "4h3h", "5c4d"],

        // 三間飛車：飛車を7筋に振る
        ["7g7f", "3c3d", "2h7h", "8c8d",
         "5i4h", "4a3b", "4h3h", "3b3c",
         "3h2h", "7a6b", "7h7i", "6b5c",
         "4i3i", "5c4d", "3i2i", "4d3e"],

        // 中飛車：飛車を5筋に振る積極策
        ["7g7f", "3c3d", "2h5h", "8c8d",
         "5g5f", "5a4b", "5i4h", "4b3b",
         "4h3h", "3b2b", "3h2h", "7a6b",
         "4i3i", "6b5c", "5f5e", "5c4d"],

        // MARK: - 後手番定跡

        // 後手矢倉（先手7六歩に対して右玉で受ける）
        ["7g7f", "8c8d", "6i7h", "7a6b",
         "3i3h", "6b7c", "5i4h", "4a3b",
         "4h3h", "3b4c", "3h2h", "4c5d",
         "2g2f", "5d4e", "2f2e", "4e5f"],

        // 後手四間飛車（先手居飛車に対して）
        ["2g2f", "3c3d", "7g7f", "4c4d",
         "2f2e", "2b4d", "3i3h", "4d5e",
         "3h2g", "5e4f", "2g3f", "4f3g+"],

        // 後手振り飛車（先手に角道を開けられた場合）
        ["7g7f", "3c3d", "2g2f", "4c4d",
         "2f2e", "2b4d", "8h7g", "4d5e",
         "7g5e", "8c8d", "5e3g", "8d8e"],
    ]

    private static let table: [String: String] = {
        var dict: [String: String] = [:]
        for line in lines {
            var pos = Position.start()
            for usi in line {
                guard let move = Move.fromUSI(usi),
                      pos.legalMoves().contains(move) else { break }
                let key = pos.toSFEN()
                if dict[key] == nil { dict[key] = usi }
                pos.make(move)
            }
        }
        return dict
    }()
}
